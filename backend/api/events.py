from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response
from api.event_input import InvalidEventError, parse_attendee_name, parse_new_event
from services.event_service import (
    DuplicateEventError, ForbiddenError, NotFoundError, ServiceUnavailableError,
)

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
        event, host_token = service.create_event(**fields)
    except DuplicateEventError:
        return error_response(409, "event_exists", "An event with this id already exists")
    except ServiceUnavailableError:
        current_app.logger.exception("Failed to save event")
        return _unavailable()

    # The host gets the full event and their secret token, once.
    body = event.to_dict() | event.location_dict()
    body["host_token"] = host_token
    return jsonify(body), 201


# Attendees and private locations. Callers prove who they are with the secret
# tokens handed out above: X-Host-Token (from creating the event) or
# X-Attendee-Token (from asking to join). All checks happen in EventService.

def _host_token():
    return request.headers.get("X-Host-Token")


def _attendee_token():
    return request.headers.get("X-Attendee-Token")


def _guarded(action):
    """Runs a service call and turns its errors into JSON responses."""
    try:
        return action()
    except NotFoundError as e:
        return error_response(404, "not_found", f"No such {e}")
    except ForbiddenError as e:
        return error_response(403, "forbidden", str(e))
    except ServiceUnavailableError:
        current_app.logger.exception("Event store unavailable")
        return _unavailable()


@events_bp.post("/<event_id>/attendees")
def request_to_join(event_id):
    try:
        name = parse_attendee_name(request.get_json(silent=True))
    except InvalidEventError as e:
        return error_response(400, "invalid_attendee", str(e))
    service = current_app.extensions["event_service"]

    def run():
        attendee, token = service.request_to_join(event_id, name)
        return jsonify(attendee.to_dict() | {"attendee_token": token}), 201
    return _guarded(run)


@events_bp.get("/<event_id>/attendees")
def list_attendees(event_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify({
        "attendees": [a.to_dict() for a in service.list_attendees(event_id, _host_token())],
    }))


@events_bp.post("/<event_id>/attendees/<attendee_id>/approve")
def approve_attendee(event_id, attendee_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify(service.approve_attendee(event_id, attendee_id, _host_token()).to_dict()))


@events_bp.delete("/<event_id>/attendees/<attendee_id>")
def remove_attendee(event_id, attendee_id):
    service = current_app.extensions["event_service"]

    def run():
        service.remove_attendee(event_id, attendee_id, _host_token(), _attendee_token())
        return "", 204
    return _guarded(run)


@events_bp.get("/<event_id>/location")
def event_location(event_id):
    service = current_app.extensions["event_service"]
    return _guarded(lambda: jsonify(
        service.location_for(event_id, _host_token(), _attendee_token()).location_dict()
    ))
