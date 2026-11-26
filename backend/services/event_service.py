"""Business logic for events and their attendees.

Every method that changes something takes the signed-in user (see
services/auth_service.py). Permission checks compare account ids: the host is
whoever created the event, and an attendee entry belongs to the user it's for.
"""
import hashlib
import logging
import secrets
import uuid
from dataclasses import replace
from datetime import datetime, timezone

from google.api_core.exceptions import GoogleAPIError
from google.auth.exceptions import GoogleAuthError

from models import APPROVED, MESSAGE_SYSTEM, PENDING, Attendee, Event, Message
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

    def delete_event(self, event_id, user):
        """The host deletes their event, with its attendees and cover. Everyone who had joined
        or asked to join is told through cancellations_for()."""
        event = self._event(event_id)
        self._require_host(event, user)
        if self._store(self._repository.delete_event, event.id, self.now()) is None:
            raise NotFoundError("event")

    def cancellations_for(self, user, limit=50):
        """Events this user joined or asked to join that their host has since deleted."""
        return self._store(self._repository.list_cancellations_for, user.id, limit)

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
            self._announce(event.id, attendee, "joined the plan")
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
        self._announce(event.id, approved, "joined the plan")
        return approved

    def set_check_in(self, event_id, attendee_id, user, checked_in):
        event = self._event(event_id)
        self._require_host(event, user)
        attendee = self._store(self._repository.set_check_in, event_id, attendee_id, checked_in)
        if attendee is None:
            raise NotFoundError("attendee")
        if attendee.status != APPROVED:
            raise ForbiddenError("Approve the guest before checking them in")
        return attendee

    def record_attendance(self, event_id, user, attended, feedback):
        """A guest says whether they went, after the event, with optional feedback for the host.
        Answering again replaces the earlier answer. Feedback is kept only when they went."""
        event = self._event(event_id)
        attendee = self._store(self._repository.get_attendee, event.id, user.id)
        if attendee is None or attendee.status != APPROVED:
            raise ForbiddenError("Only guests of this event can say whether they went")
        if (event.end_time or event.start_time) > self.now():
            raise ForbiddenError("You can answer once the event is over")
        attendee = self._store(self._repository.set_attendance, event.id, user.id, attended,
                               feedback if attended else None, self.now())
        if attendee is None:
            raise NotFoundError("attendee")
        return attendee

    def remove_attendee(self, event_id, attendee_id, user):
        """The host can remove anyone (or decline a request); anyone else only themselves."""
        event = self._event(event_id)
        attendee = self._attendee(event.id, attendee_id)
        if not (self._is_host(event, user) or attendee.id == user.id):
            raise ForbiddenError("Only the host or this attendee can do this")
        delta = -1 if attendee.status == APPROVED else 0
        self._update_attendance(event.id, attendee, delta, delete=True)
        if attendee.status == APPROVED:   # a withdrawn or declined request was never in the chat
            self._announce(event.id, attendee, "left the plan" if attendee.id == user.id else "was removed from the plan")

    def location_for(self, event_id, user):
        """The full location, for the host or an approved attendee of this event."""
        event = self._event(event_id)
        if not event.location_private or self._is_host(event, user):
            return event
        attendee = self._store(self._repository.get_attendee, event.id, user.id)
        if attendee is not None and attendee.status == APPROVED:
            return event
        raise ForbiddenError("The location is shared once the host approves your request")

    # MARK: Group chat. One chat per plan, for the host and approved guests.

    def _require_member(self, event, user):
        if self._is_host(event, user):
            return
        attendee = self._store(self._repository.get_attendee, event.id, user.id)
        if attendee is None or attendee.status != APPROVED:
            raise ForbiddenError("The chat is for the host and approved guests")

    def post_message(self, event_id, user, text, client_id=None):
        """Adds `text` to the plan's chat. Returns (message, created); sending the same
        client_id again returns the first message instead of a copy."""
        event = self._event(event_id)
        self._require_member(event, user)
        message = self._message(event.id, user.id, user.name, text, client_id=client_id)
        result = self._store(self._repository.add_message, message)
        if result is None:
            raise NotFoundError("event")
        return result

    def _message(self, event_id, sender_id, sender_name, text, **fields):
        now = self._clock()
        # Key order is time order (see models.Message); the suffix keeps same-ms ids apart.
        return Message(id=f"{int(now.timestamp() * 1000):013d}-{secrets.token_hex(4)}", event_id=event_id,
                       sender_id=sender_id, sender_name=sender_name, text=text, created_at=now, **fields)

    def _announce(self, event_id, attendee, what):
        """A system line in the plan's chat ("Maya joined the plan"), written by the server so every phone
        shows the same one. Best effort: the join or leave already happened, so a failure is only logged."""
        first_name = (attendee.name.split() or ["Someone"])[0]
        message = self._message(event_id, attendee.id, attendee.name, f"{first_name} {what}", kind=MESSAGE_SYSTEM)
        try:
            self._repository.add_message(message)
        except _STORE_ERRORS:
            logging.exception("Couldn't add %r to the chat of event %s", message.text, event_id)

    def list_messages(self, event_id, user, after_id, limit):
        """(messages after `after_id`, oldest first, has_more). From the start without `after_id`."""
        event = self._event(event_id)
        self._require_member(event, user)
        found = self._store(self._repository.list_messages, event.id, after_id, limit + 1)
        return found[:limit], len(found) > limit

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
