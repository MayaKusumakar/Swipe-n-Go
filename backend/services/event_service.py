"""Business logic for events."""
from datetime import datetime, timezone

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError


class ServiceUnavailableError(Exception):
    """The event store could not be reached."""


def _utc_now():
    return datetime.now(timezone.utc)


class EventService:
    def __init__(self, repository, clock=_utc_now):
        self._repository = repository
        self._clock = clock

    def list_upcoming_events(self, limit):
        try:
            return self._repository.list_upcoming(self._clock(), limit)
        # OSError: no GCP project configured, or a network failure.
        except (GoogleAPIError, GoogleAuthError, OSError) as e:
            raise ServiceUnavailableError("Event store unavailable") from e
