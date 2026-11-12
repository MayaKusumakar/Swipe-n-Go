"""Business logic for events and their attendees.

Every method that changes something takes the signed-in user (see
services/auth_service.py). Permission checks compare account ids: the host is
whoever created the event, and an attendee entry belongs to the user it's for.
"""
import hashlib
import uuid
from dataclasses import replace
from datetime import datetime, timezone

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError

from models import APPROVED, PENDING, Attendee, Event
from services import geo, matching


class ServiceUnavailableError(Exception):
    """The event store could not be reached."""


class DuplicateEventError(Exception):
    """An event with the requested id already exists."""


class NotFoundError(Exception):
    """The event or attendee does not exist."""


class ForbiddenError(Exception):
    """The signed-in user isn't allowed to do this."""


class EventFullError(Exception):
    """The event has no spots left."""


def _utc_now():
    return datetime.now(timezone.utc)


# OSError: no GCP project configured, or a network failure.
_STORE_ERRORS = (GoogleAPIError, GoogleAuthError, OSError)


class EventService:
    def __init__(self, repository, clock=_utc_now):
        self._repository = repository
        self._clock = clock

    @property
    def repository(self):
        return self._repository

    def now(self):
        return self._clock()

    def list_upcoming_events(self, limit):
        try:
            return self._repository.list_upcoming(self._clock(), limit)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e

    def create_event(self, user, event_id=None, **fields):
        """Stores a new event hosted by `user`. `fields` are already validated
        (see api/event_input.py). The host's name comes from their account."""
        fields["host_name"] = user.name
        # New events get a summary on the next /tasks/summarize-stale run.
        event = Event(id=event_id or str(uuid.uuid4()), host_id=user.id, summary_stale=True, **fields)
        if event.location_private:
            # A hidden location is only revealed through approval, so approval is required.
            event.requires_approval = True
        try:
            if not self._repository.add(event):
                raise DuplicateEventError(event.id)
        except _STORE_ERRORS as e:
            raise ServiceUnavailableError("Event store unavailable") from e
        return event

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

    @staticmethod
    def _is_host(event, user):
        return event.host_id is not None and event.host_id == user.id

    def _require_host(self, event, user):
        if not self._is_host(event, user):
            raise ForbiddenError("Only the host can do this")

    def _update_attendance(self, event_id, attendee, delta, delete=False):
        """Saves the attendee and adjusts attendee_count together (see the repository)."""
        result = self._store(self._repository.update_attendance, event_id, attendee, delta, delete)
        if result is None:
            raise NotFoundError("event")
        if result is False:
            raise EventFullError("This event is full")

    def rename_host(self, user_id, name):
        """After someone changes their name, their events show the new one."""
        return self._store(self._repository.rename_host, user_id, name)

    def get_event(self, event_id):
        return self._event(event_id)

    # MARK: Cover photos

    def set_cover(self, event_id, user, data):
        """The host's cover photo (validated JPEG bytes). Returns the event's new image_url."""
        event = self._event(event_id)
        if not self._is_host(event, user):
            raise ForbiddenError("Only the host can change the cover photo")
        # The version changes with the picture, so phones know to download it again.
        image_url = f"/api/events/{event.id}/cover?v={hashlib.sha256(data).hexdigest()[:12]}"
        if not self._store(self._repository.save_cover, event.id, data, image_url):
            raise NotFoundError("event")
        return image_url

    def cover(self, event_id):
        data = self._store(self._repository.get_cover, event_id)
        if data is None:
            raise NotFoundError("cover photo")
        return data

    def request_to_join(self, event_id, user):
        """Returns (attendee, created). Approved at once unless the event needs approval.
        Asking again returns the existing entry instead of a second one."""
        event = self._event(event_id)
        if self._is_host(event, user):
            raise ForbiddenError("You're hosting this event")
        existing = self._store(self._repository.get_attendee, event.id, user.id)
        if existing is not None:
            return existing, False
        attendee = Attendee(
            id=user.id, event_id=event.id, name=user.name,
            status=PENDING if event.requires_approval else APPROVED, created_at=self._clock(),
        )
        if attendee.status == APPROVED:
            # Counts toward attendee_count right away; refused if the event is full.
            self._update_attendance(event.id, attendee, +1)
        else:
            # A request doesn't take a spot until the host approves it.
            self._store(self._repository.save_attendee, attendee)
        return attendee, True

    def my_attendance(self, event_id, user):
        """Your own entry for an event, so the app can see when the host approved you."""
        self._event(event_id)
        return self._attendee(event_id, user.id)

    def list_attendees(self, event_id, user):
        event = self._event(event_id)
        self._require_host(event, user)
        return self._store(self._repository.list_attendees, event.id)

    def approve_attendee(self, event_id, attendee_id, user):
        event = self._event(event_id)
        self._require_host(event, user)
        attendee = self._attendee(event.id, attendee_id)
        if attendee.status == APPROVED:
            return attendee
        approved = replace(attendee, status=APPROVED)
        self._update_attendance(event.id, approved, +1)
        return approved

    def remove_attendee(self, event_id, attendee_id, user):
        """The host can remove anyone (or decline a request); anyone else only themselves."""
        event = self._event(event_id)
        attendee = self._attendee(event.id, attendee_id)
        if not (self._is_host(event, user) or attendee.id == user.id):
            raise ForbiddenError("Only the host or this attendee can do this")
        delta = -1 if attendee.status == APPROVED else 0
        self._update_attendance(event.id, attendee, delta, delete=True)

    def location_for(self, event_id, user):
        """The full location, for the host or an approved attendee of this event."""
        event = self._event(event_id)
        if not event.location_private or self._is_host(event, user):
            return event
        attendee = self._store(self._repository.get_attendee, event.id, user.id)
        if attendee is not None and attendee.status == APPROVED:
            return event
        raise ForbiddenError("The location is shared once the host approves your request")

    # MARK: Nearby and recommended. Private locations are never searched by
    # place, so their position can't be narrowed down by searching from
    # different spots.

    def nearby_events(self, latitude, longitude, radius_miles, limit):
        """Upcoming public-location events within radius_miles, soonest first.

        Returns a list of (event, distance_miles).
        """
        now = self._clock()
        radius_km = radius_miles * geo.KM_PER_MILE
        cells = geo.covering_cells(latitude, longitude, radius_km)
        found = []
        for event in self._store(self._repository.list_in_geohash_cells, cells):
            if event.location_private or event.start_time < now or event.latitude is None:
                continue
            distance = geo.distance_km(latitude, longitude, event.latitude, event.longitude)
            if distance <= radius_km:
                found.append((event, distance / geo.KM_PER_MILE))
        found.sort(key=lambda pair: pair[0].start_time)
        return found[:limit]

    def recommended_events(self, interests, limit, latitude=None, longitude=None, radius_miles=None):
        """Events that match `interests`, best match first.

        With a location, candidates are the nearby events; without one, the
        next upcoming events. Returns a list of (event, score, distance_miles).
        """
        if latitude is not None:
            candidates = self.nearby_events(latitude, longitude, radius_miles, matching.MAX_CANDIDATES)
        else:
            candidates = [(e, None) for e in self.list_upcoming_events(matching.MAX_CANDIDATES)]
        ranked = matching.rank(interests, candidates)
        return ranked[:limit]
