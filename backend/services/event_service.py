"""Business logic for events."""
import uuid
from datetime import datetime, timezone

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError

from models import Event


class ServiceUnavailableError(Exception):
    """The event store could not be reached."""


class DuplicateEventError(Exception):
    """An event with the requested id already exists."""


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
        """Stores a new event. `fields` are already validated (see api/event_input.py)."""
        event = Event(id=event_id or str(uuid.uuid4()), **fields)
        try:
            if not self._repository.add(event):
                raise DuplicateEventError(event.id)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e
        return event
