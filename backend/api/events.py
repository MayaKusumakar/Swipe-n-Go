from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response
from services.event_service import ServiceUnavailableError

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
        return error_response(
            503, "datastore_unavailable", "Events are temporarily unavailable"
        )

    return jsonify({
        "events": [event.to_dict() for event in events],
        "count": len(events),
    })
