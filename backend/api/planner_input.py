"""Validation for the POST /api/planner request body."""
from datetime import datetime

from services.planner_service import CandidateEvent

MAX_QUERY = 300
MAX_EVENTS = 80
MAX_INTERESTS = 15
MAX_TEXT = 120


class InvalidPlannerRequestError(ValueError):
    pass


def _time(value, name):
    if not isinstance(value, str):
        raise InvalidPlannerRequestError(f"{name} must be an ISO-8601 string")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        raise InvalidPlannerRequestError(f"{name} must be an ISO-8601 date-time") from None
    if parsed.tzinfo is None:
        raise InvalidPlannerRequestError(f"{name} must include a UTC offset")
    return parsed


def _text(value, name, limit=MAX_TEXT, required=True):
    if value is None and not required:
        return ""
    if not isinstance(value, str) or (required and not value.strip()):
        raise InvalidPlannerRequestError(f"{name} must be a non-empty string")
    return value.strip()[:limit]


def _int(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise InvalidPlannerRequestError(f"{name} must be an integer from {low} to {high}")
    return value


def _event(raw, index):
    if not isinstance(raw, dict):
        raise InvalidPlannerRequestError(f"events[{index}] must be an object")
    distance = raw.get("distance_miles")
    if distance is not None and (isinstance(distance, bool) or not isinstance(distance, (int, float)) or distance < 0):
        raise InvalidPlannerRequestError(f"events[{index}].distance_miles must be a positive number")
    tags = raw.get("tags") or []
    if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
        raise InvalidPlannerRequestError(f"events[{index}].tags must be a list of strings")
    requires_approval = raw.get("requires_approval", False)
    if not isinstance(requires_approval, bool):
        raise InvalidPlannerRequestError(f"events[{index}].requires_approval must be true or false")
    return CandidateEvent(
        id=_text(raw.get("id"), f"events[{index}].id", 64),
        title=_text(raw.get("title"), f"events[{index}].title"),
        category=_text(raw.get("category"), f"events[{index}].category", 30),
        start_time=_time(raw.get("start_time"), f"events[{index}].start_time"),
        duration_minutes=_int(raw.get("duration_minutes"), f"events[{index}].duration_minutes", 1, 24 * 60),
        location_name=_text(raw.get("location_name"), f"events[{index}].location_name"),
        distance_miles=round(float(distance), 1) if distance is not None else None,
        cost=_text(raw.get("cost"), f"events[{index}].cost", 40, required=False) or "Free",
        level=_text(raw.get("level"), f"events[{index}].level", 20, required=False) or "anyone",
        attendee_count=_int(raw.get("attendee_count", 0), f"events[{index}].attendee_count", 0, 10_000),
        spots_left=_int(raw.get("spots_left", 0), f"events[{index}].spots_left", 0, 10_000),
        requires_approval=requires_approval,
        tags=tuple(t.strip()[:30] for t in tags[:10]),
    )


def parse_planner_request(body):
    """Returns (query, now, interests, events) or raises InvalidPlannerRequestError."""
    if not isinstance(body, dict):
        raise InvalidPlannerRequestError("request body must be a JSON object")
    query = _text(body.get("query"), "query", MAX_QUERY)
    now = _time(body.get("now"), "now")

    interests = body.get("interests") or []
    if not isinstance(interests, list) or len(interests) > MAX_INTERESTS or not all(isinstance(i, str) for i in interests):
        raise InvalidPlannerRequestError(f"interests must be a list of up to {MAX_INTERESTS} strings")

    events = body.get("events")
    if not isinstance(events, list) or len(events) > MAX_EVENTS:
        raise InvalidPlannerRequestError(f"events must be a list of up to {MAX_EVENTS} events")
    parsed = [_event(e, i) for i, e in enumerate(events)]
    if len({e.id for e in parsed}) != len(parsed):
        raise InvalidPlannerRequestError("event ids must be unique")
    return query, now, [i.strip()[:30] for i in interests], parsed
