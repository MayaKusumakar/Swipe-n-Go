"""Business logic for events and their attendees."""
import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timezone

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError

from models import APPROVED, PENDING, Attendee, Event


class ServiceUnavailableError(Exception):
    """The event store could not be reached."""


class DuplicateEventError(Exception):
    """An event with the requested id already exists."""


class NotFoundError(Exception):
    """The event or attendee does not exist."""


class ForbiddenError(Exception):
    """The caller's token does not allow this action."""


def _new_token():
    return secrets.token_urlsafe(32)


def _hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def _matches(token, token_hash):
    return bool(token) and bool(token_hash) and hmac.compare_digest(_hash(token), token_hash)


def _utc_now():
    return datetime.now(timezone.utc)


# OSError: no GCP project configured, or a network failure.
_STORE_ERRORS = (GoogleAPIError, GoogleAuthError, OSError)


class EventService:
    def __init__(self, repository, clock=_utc_now):
        self._repository = repository
        self._clock = clock

    def now(self):
        return self._clock()

    def list_upcoming_events(self, limit):
        try:
            return self._repository.list_upcoming(self._clock(), limit)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e

    def create_event(self, event_id=None, **fields):
        """Stores a new event. `fields` are already validated (see api/event_input.py).

        Returns (event, host_token). The host token is shown once; only its hash is stored.
        """
        host_token = _new_token()
        event = Event(id=event_id or str(uuid.uuid4()), host_token_hash=_hash(host_token), **fields)
        if event.location_private:
            # A hidden location is only revealed through approval, so approval is required.
            event.requires_approval = True
        try:
            if not self._repository.add(event):
                raise DuplicateEventError(event.id)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e
        return event, host_token

    # MARK: Attendees. Every check below runs on the server; the app only hides buttons.

    def _store(self, call, *args):
        try:
            return call(*args)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e

    def _event(self, event_id):
        event = self._store(self._repository.get, event_id)
        if event is None:
            raise NotFoundError("event")
        return event

    def _attendee(self, event_id, attendee_id):
        attendee = self._store(self._repository.get_attendee, event_id, attendee_id)
        if attendee is None:
            raise NotFoundError("attendee")
        return attendee

    def _require_host(self, event, host_token):
        if not _matches(host_token, event.host_token_hash):
            raise ForbiddenError("Only the host can do this")

    def request_to_join(self, event_id, name):
        """Returns (attendee, attendee_token). Approved at once unless the event needs approval."""
        event = self._event(event_id)
        token = _new_token()
        attendee = Attendee(
            id=str(uuid.uuid4()), event_id=event.id, name=name,
            status=PENDING if event.requires_approval else APPROVED,
            token_hash=_hash(token), created_at=self._clock(),
        )
        self._store(self._repository.save_attendee, attendee)
        return attendee, token

    def list_attendees(self, event_id, host_token):
        event = self._event(event_id)
        self._require_host(event, host_token)
        return self._store(self._repository.list_attendees, event.id)

    def approve_attendee(self, event_id, attendee_id, host_token):
        event = self._event(event_id)
        self._require_host(event, host_token)
        attendee = self._attendee(event.id, attendee_id)
        attendee.status = APPROVED
        self._store(self._repository.save_attendee, attendee)
        return attendee

    def remove_attendee(self, event_id, attendee_id, host_token=None, attendee_token=None):
        """The host can remove anyone (or decline a request); an attendee can remove only themselves."""
        event = self._event(event_id)
        attendee = self._attendee(event.id, attendee_id)
        if not (_matches(host_token, event.host_token_hash) or _matches(attendee_token, attendee.token_hash)):
            raise ForbiddenError("Only the host or this attendee can do this")
        self._store(self._repository.delete_attendee, event.id, attendee.id)

    def location_for(self, event_id, host_token=None, attendee_token=None):
        """The full location, for the host or an approved attendee of this event."""
        event = self._event(event_id)
        if not event.location_private or _matches(host_token, event.host_token_hash):
            return event
        if attendee_token:
            token_hash = _hash(attendee_token)
            for attendee in self._store(self._repository.list_attendees, event.id):
                if attendee.status == APPROVED and hmac.compare_digest(token_hash, attendee.token_hash):
                    return event
        raise ForbiddenError("The location is shared once the host approves your request")
