from flask import Blueprint, current_app, g, jsonify, request

from api.errors import error_response
from api.event_input import InvalidEventError, parse_new_event
from services.event_service import (
    DuplicateEventError, EventFullError, ForbiddenError, NotFoundError, ServiceUnavailableError,
)

events_bp = Blueprint("events", __name__, url_prefix="/api/events")

DEFAULT_LIMIT = 20
MAX_LIMIT = 50
DEFAULT_RADIUS_MILES = 5
MAX_RADIUS_MILES = 25
MAX_INTERESTS = 15
MAX_INTEREST_LENGTH = 30


class InvalidParameterError(ValueError):
    pass


def _parse_limit(raw):
    """Returns the limit as an int, or None if it is invalid."""
    if raw is None:
        return DEFAULT_LIMIT
    try:
        limit = int(raw, 10)
    except ValueError:
        return None
    return limit if 1 <= limit <= MAX_LIMIT else None


def _float_param(name, low, high, default=None):
    raw = request.args.get(name)
    if raw is None:
        if default is None:
            raise InvalidParameterError(f"{name} is required")
        return float(default)
    try:
        value = float(raw)
    except ValueError:
        raise InvalidParameterError(f"{name} must be a number from {low} to {high}") from None
    if not low <= value <= high:  # also rejects nan
        raise InvalidParameterError(f"{name} must be a number from {low} to {high}")
    return value


def _location_params(required):
    """(latitude, longitude, radius_miles), or (None, None, None) when optional and absent."""
    if not required and request.args.get("lat") is None and request.args.get("lng") is None:
        return None, None, None
    return (
        _float_param("lat", -90, 90),
        _float_param("lng", -180, 180),
        _float_param("radius_miles", 0.1, MAX_RADIUS_MILES, DEFAULT_RADIUS_MILES),
    )


def _interests_param():
    interests = [i.strip() for i in request.args.get("interests", "").split(",") if i.strip()]
    if not interests or len(interests) > MAX_INTERESTS or any(len(i) > MAX_INTEREST_LENGTH for i in interests):
        raise InvalidParameterError(
            f"interests must be 1 to {MAX_INTERESTS} comma-separated words, each up to {MAX_INTEREST_LENGTH} characters"
        )
    return interests


def _miles(distance):
    return round(distance, 2) if distance is not None else None


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


@events_bp.get("/nearby")
def nearby_events():
    """Upcoming events within radius_miles of lat/lng. Private locations are left out."""
    limit = _parse_limit(request.args.get("limit"))
    try:
        if limit is None:
            raise InvalidParameterError(f"limit must be an integer from 1 to {MAX_LIMIT}")
        latitude, longitude, radius = _location_params(required=True)
    except InvalidParameterError as e:
        return error_response(400, "invalid_parameter", str(e))

    service = current_app.extensions["event_service"]

    def run():
        found = service.nearby_events(latitude, longitude, radius, limit)
        return jsonify({
            "events": [event.to_dict() | {"distance_miles": _miles(d)} for event, d in found],
            "count": len(found),
        })
    return _guarded(run)


@events_bp.get("/recommended")
def recommended_events():
    """Events matching the student's interests, best match first. Free: no AI calls."""
    limit = _parse_limit(request.args.get("limit"))
    try:
        if limit is None:
            raise InvalidParameterError(f"limit must be an integer from 1 to {MAX_LIMIT}")
        interests = _interests_param()
        latitude, longitude, radius = _location_params(required=False)
    except InvalidParameterError as e:
        return error_response(400, "invalid_parameter", str(e))

    service = current_app.extensions["event_service"]

    def run():
        ranked = service.recommended_events(interests, limit, latitude, longitude, radius)
        return jsonify({
            "events": [event.to_dict() | {"match_score": score, "distance_miles": _miles(d)}
                       for event, score, d in ranked],
            "count": len(ranked),
        })
    return _guarded(run)


@events_bp.post("")
def create_event():
    body = request.get_json(silent=True)
    service = current_app.extensions["event_service"]
    try:
        fields = parse_new_event(body, service.now())
    except InvalidEventError as e:
        return error_response(400, "invalid_event", str(e))

    try:
        event = service.create_event(g.user, **fields)
    except DuplicateEventError:
        return error_response(409, "event_exists", "An event with this id already exists")
    except ServiceUnavailableError:
        current_app.logger.exception("Failed to save event")
        return _unavailable()

    # The host gets the full event, including a private location.
    return jsonify(event.to_dict() | event.location_dict()), 201


# Attendees and private locations. The signed-in user (g.user, set in
# api/auth.py) is who's asking; all permission checks happen in EventService.

def _guarded(action):
    """Runs a service call and turns its errors into JSON responses."""
    try:
        return action()
    except NotFoundError as e:
        return error_response(404, "not_found", f"No such {e}")
    except ForbiddenError as e:
        return error_response(403, "forbidden", str(e))
    except EventFullError as e:
        return error_response(409, "event_full", str(e))
    except ServiceUnavailableError:
        current_app.logger.exception("Event store unavailable")
        return _unavailable()


@events_bp.post("/<event_id>/attendees")
def request_to_join(event_id):
    service = current_app.extensions["event_service"]

    def run():
        attendee, created = service.request_to_join(event_id, g.user)
        return jsonify(attendee.to_dict()), 201 if created else 200
    return _guarded(run)


@events_bp.get("/<event_id>/attendees/me")
def my_attendance(event_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify(service.my_attendance(event_id, g.user).to_dict()))


@events_bp.get("/<event_id>/attendees")
def list_attendees(event_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify({
        "attendees": [a.to_dict() for a in service.list_attendees(event_id, g.user)],
    }))


@events_bp.post("/<event_id>/attendees/<attendee_id>/approve")
def approve_attendee(event_id, attendee_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify(service.approve_attendee(event_id, attendee_id, g.user).to_dict()))


@events_bp.delete("/<event_id>/attendees/<attendee_id>")
def remove_attendee(event_id, attendee_id):
    service = current_app.extensions["event_service"]

    def run():
        service.remove_attendee(event_id, attendee_id, g.user)
        return "", 204
    return _guarded(run)


@events_bp.get("/<event_id>/location")
def event_location(event_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify(service.location_for(event_id, g.user).location_dict()))
