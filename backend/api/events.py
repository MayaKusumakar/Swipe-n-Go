from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response
from api.event_input import InvalidEventError, parse_new_event
from services.event_service import DuplicateEventError, ServiceUnavailableError

events_bp = Blueprint("events", __name__, url_prefix="/api/events")

DEFAULT_LIMIT = 20
MAX_LIMIT = 50


def _parse_limit(raw):
    """Returns the limit as an int, or None if it is invalid."""
    if raw is None:
        return DEFAULT_LIMIT
    try:
        limit = int(raw, 10)
    except ValueError:
        return None
    return limit if 1 <= limit <= MAX_LIMIT else None


def _unavailable():
    return error_response(503, "datastore_unavailable", "Events are temporarily unavailable")


@events_bp.get("")
def list_events():
    limit = _parse_limit(request.args.get("limit"))
    if limit is None:
        return error_response(
            400, "invalid_parameter",
            f"limit must be an integer from 1 to {MAX_LIMIT}",
        )

    service = current_app.extensions["event_service"]
    try:
        events = service.list_upcoming_events(limit)
    except ServiceUnavailableError:
        current_app.logger.exception("Failed to load events")
        return _unavailable()

    return jsonify({
        "events": [event.to_dict() for event in events],
        "count": len(events),
    })


@events_bp.post("")
def create_event():
    body = request.get_json(silent=True)
    service = current_app.extensions["event_service"]
    try:
        fields = parse_new_event(body, service.now())
    except InvalidEventError as e:
        return error_response(400, "invalid_event", str(e))

    try:
        event = service.create_event(**fields)
    except DuplicateEventError:
        return error_response(409, "event_exists", "An event with this id already exists")
    except ServiceUnavailableError:
        current_app.logger.exception("Failed to save event")
        return _unavailable()

    return jsonify(event.to_dict()), 201
