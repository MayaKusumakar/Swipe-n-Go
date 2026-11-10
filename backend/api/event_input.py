"""Validation for the POST /api/events request body.

parse_new_event() turns untrusted JSON into clean keyword arguments for
EventService.create_event(), or raises InvalidEventError naming the bad field.
"""
import re
import uuid
from datetime import datetime

from models import LEVELS

MAX_TITLE = 120
MAX_DESCRIPTION = 2000
MAX_SHORT_TEXT = 120
MAX_TAGS = 10
MAX_TAG_LENGTH = 30
MIN_CAPACITY = 2
MAX_CAPACITY = 500
CATEGORY_PATTERN = re.compile(r"^[a-z][a-z_]{0,29}$")


class InvalidEventError(ValueError):
    def __init__(self, field, message):
        super().__init__(message)
        self.field = field


def _text(body, name, max_length, required=False):
    value = body.get(name)
    if value is None:
        if required:
            raise InvalidEventError(name, f"{name} is required")
        return None
    if not isinstance(value, str):
        raise InvalidEventError(name, f"{name} must be a string")
    value = value.strip()
    if required and not value:
        raise InvalidEventError(name, f"{name} must not be empty")
    if len(value) > max_length:
        raise InvalidEventError(name, f"{name} must be at most {max_length} characters")
    return value or None


def _time(body, name, required=False):
    value = body.get(name)
    if value is None:
        if required:
            raise InvalidEventError(name, f"{name} is required")
        return None
    if not isinstance(value, str):
        raise InvalidEventError(name, f"{name} must be an ISO-8601 string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise InvalidEventError(name, f"{name} must be an ISO-8601 date-time") from None
    if parsed.tzinfo is None:
        raise InvalidEventError(name, f"{name} must include a UTC offset")
    return parsed


def _coordinate(body, name, limit):
    value = body.get(name)
    if value is None:
        return None
    # bool is an int subclass; reject it explicitly.
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not -limit <= value <= limit:
        raise InvalidEventError(name, f"{name} must be a number from -{limit} to {limit}")
    return float(value)


def parse_new_event(body, now):
    if not isinstance(body, dict):
        raise InvalidEventError("body", "request body must be a JSON object")

    event_id = body.get("id")
    if event_id is not None:
        # Clients may supply their own UUID so the event keeps one id everywhere.
        try:
            event_id = str(uuid.UUID(str(event_id)))
        except ValueError:
            raise InvalidEventError("id", "id must be a UUID") from None

    start_time = _time(body, "start_time", required=True)
    if start_time < now:
        raise InvalidEventError("start_time", "start_time must be in the future")
    end_time = _time(body, "end_time")
    if end_time is not None and end_time <= start_time:
        raise InvalidEventError("end_time", "end_time must be after start_time")

    category = body.get("category")
    if not isinstance(category, str) or not CATEGORY_PATTERN.match(category):
        raise InvalidEventError("category", "category must be a lowercase word like \"run\" or \"food\"")

    latitude = _coordinate(body, "latitude", 90)
    longitude = _coordinate(body, "longitude", 180)
    if (latitude is None) != (longitude is None):
        raise InvalidEventError("latitude", "latitude and longitude must be sent together")

    capacity = body.get("capacity")
    if capacity is not None and (
        isinstance(capacity, bool) or not isinstance(capacity, int)
        or not MIN_CAPACITY <= capacity <= MAX_CAPACITY
    ):
        raise InvalidEventError("capacity", f"capacity must be an integer from {MIN_CAPACITY} to {MAX_CAPACITY}")

    tags = body.get("tags", [])
    if not isinstance(tags, list) or len(tags) > MAX_TAGS or not all(
        isinstance(tag, str) and 0 < len(tag.strip()) <= MAX_TAG_LENGTH for tag in tags
    ):
        raise InvalidEventError("tags", f"tags must be a list of up to {MAX_TAGS} short strings")

    level = body.get("level")
    if level is not None and level not in LEVELS:
        raise InvalidEventError("level", f"level must be one of: {', '.join(LEVELS)}")

    requires_approval = body.get("requires_approval", False)
    if not isinstance(requires_approval, bool):
        raise InvalidEventError("requires_approval", "requires_approval must be true or false")

    return {
        "event_id": event_id,
        "title": _text(body, "title", MAX_TITLE, required=True),
        "description": _text(body, "description", MAX_DESCRIPTION) or "",
        "start_time": start_time,
        "end_time": end_time,
        "location_name": _text(body, "location_name", MAX_SHORT_TEXT, required=True),
        "latitude": latitude,
        "longitude": longitude,
        "category": category,
        "host_name": _text(body, "host_name", MAX_SHORT_TEXT),
        "address": _text(body, "address", MAX_SHORT_TEXT),
        "capacity": capacity,
        "cost": _text(body, "cost", 40),
        "tags": [tag.strip() for tag in tags],
        "level": level,
        "requires_approval": requires_approval,
    }
