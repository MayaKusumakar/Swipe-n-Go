import sys
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Let tests import backend modules (main, models, ...) the same way App Engine does.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from main import create_app  # noqa: E402
from models import APPROVED, Cancellation, Event  # noqa: E402
from repositories.user_repository import InMemoryUserRepository  # noqa: E402
from services.auth_service import AuthService  # noqa: E402
from services.event_service import EventService  # noqa: E402

FIXED_NOW = datetime(2026, 11, 5, 12, 0, tzinfo=timezone.utc)


class FakeEventRepository:
    """Stands in for Datastore. Set `events` or `error` per test."""

    def __init__(self):
        self.events = []
        self.attendees = {}
        self.cancellations = {}
        self.messages = {}  # event_id -> [Message]
        self.error = None
        self.calls = []

    def list_upcoming(self, now, limit):
        self.calls.append((now, limit))
        if self.error:
            raise self.error
        return self.events[:limit]

    def add(self, event):
        if self.error:
            raise self.error
        if any(e.id == event.id for e in self.events):
            return False
        self.events.append(event)
        return True

    def get(self, event_id):
        if self.error:
            raise self.error
        return next((e for e in self.events if e.id == event_id), None)

    def delete_event(self, event_id, cancelled_at):
        if self.error:
            raise self.error
        event = self.get(event_id)
        if event is None:
            return None
        guests = [attendee_id for (eid, attendee_id) in self.attendees if eid == event_id]
        cancellation = Cancellation.for_event(event, guests, cancelled_at)
        if guests:
            self.cancellations[event_id] = cancellation
        self.events = [e for e in self.events if e.id != event_id]
        self.attendees = {key: a for key, a in self.attendees.items() if key[0] != event_id}
        self.messages.pop(event_id, None)
        return cancellation

    def list_cancellations_for(self, user_id, limit):
        if self.error:
            raise self.error
        found = [c for c in self.cancellations.values() if user_id in c.attendee_ids]
        return sorted(found, key=lambda c: c.cancelled_at, reverse=True)[:limit]

    def list_in_geohash_cells(self, prefixes):
        self.calls.append(("cells", tuple(prefixes)))
        if self.error:
            raise self.error
        return [e for e in self.events if e.geohash and e.geohash.startswith(tuple(prefixes))]

    def list_stale_summaries(self, limit):
        return [e for e in self.events if e.summary_stale][:limit]

    def save_summary(self, event_id, summary, updated_at, attendee_count):
        event = self.get(event_id)
        if event is not None:
            event.summary, event.summary_updated_at = summary, updated_at
            event.summary_stale = event.attendee_count != attendee_count

    def update_attendance(self, event_id, attendee, delta, delete=False):
        if self.error:
            raise self.error
        event = self.get(event_id)
        if event is None:
            return None
        if delta > 0 and event.is_full:
            return False
        event.attendee_count = max(0, event.attendee_count + delta)
        if delta:
            event.summary_stale = True
        if delete:
            self.attendees.pop((event_id, attendee.id), None)
        else:
            self.attendees[(event_id, attendee.id)] = attendee
        return True

    def list_attendees(self, event_id):
        return sorted((a for (eid, _), a in self.attendees.items() if eid == event_id),
                      key=lambda a: a.created_at)

    def get_attendee(self, event_id, attendee_id):
        return self.attendees.get((event_id, attendee_id))

    def set_check_in(self, event_id, attendee_id, checked_in):
        key = (event_id, attendee_id)
        attendee = self.attendees.get(key)
        if attendee is not None and attendee.status == APPROVED:
            attendee = replace(attendee, checked_in=checked_in)
            self.attendees[key] = attendee
        return attendee

    def set_attendance(self, event_id, attendee_id, attended, feedback, answered_at):
        key = (event_id, attendee_id)
        attendee = self.attendees.get(key)
        if attendee is None:
            return None
        attendee = replace(attendee, attended=attended, feedback=feedback, feedback_at=answered_at)
        self.attendees[key] = attendee
        return attendee

    def save_attendee(self, attendee):
        self.attendees[(attendee.event_id, attendee.id)] = attendee

    def delete_attendee(self, event_id, attendee_id):
        self.attendees.pop((event_id, attendee_id), None)

    def add_message(self, message):
        if self.error:
            raise self.error
        if self.get(message.event_id) is None:
            return None
        chat = self.messages.setdefault(message.event_id, [])
        existing = next((m for m in chat if message.client_id and m.client_id == message.client_id), None)
        if existing is not None:
            return existing, False
        chat.append(message)
        chat.sort(key=lambda m: m.id)
        return message, True

    def list_messages(self, event_id, after_id, limit):
        if self.error:
            raise self.error
        chat = self.messages.get(event_id, [])
        return [m for m in chat if after_id is None or m.id > after_id][:limit]


def make_event(event_id="seed-001", **overrides):
    fields = dict(
        id=event_id,
        title="Trivia Night",
        description="Teams of up to 6.",
        start_time=datetime(2026, 11, 6, 19, 0, tzinfo=timezone.utc),
        end_time=datetime(2026, 11, 6, 21, 0, tzinfo=timezone.utc),
        location_name="Memorial Union",
        latitude=38.5424,
        longitude=-121.7494,
        category="social",
        image_url=None,
    )
    fields.update(overrides)
    return Event(**fields)


@pytest.fixture
def repository():
    return FakeEventRepository()


# Tests sign in with dev tokens ("dev:<email>:<name>"); real Google tokens are
# covered in test_auth.py.
HOST_NAME = "Avery"


def as_user(name):
    """Authorization header for a @ucdavis.edu user called `name`."""
    return {"Authorization": f"Bearer dev:{name.lower()}@ucdavis.edu:{name}"}


def user_id(name):
    return f"dev-{name.lower()}@ucdavis.edu"


def signed_in(app, name=HOST_NAME):
    """A test client that sends `name`'s sign-in with every request."""
    client = app.test_client()
    client.environ_base["HTTP_AUTHORIZATION"] = as_user(name)["Authorization"]
    return client


def make_app(event_service=None, **services):
    return create_app(event_service, auth_service=AuthService(client_ids=[], dev_mode=True),
                      user_repository=InMemoryUserRepository(), **services)


@pytest.fixture
def client(repository):
    return signed_in(make_app(EventService(repository, clock=lambda: FIXED_NOW)))
