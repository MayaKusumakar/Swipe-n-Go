import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Let tests import backend modules (main, models, ...) the same way App Engine does.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from main import create_app  # noqa: E402
from models import Event  # noqa: E402
from services.event_service import EventService  # noqa: E402

FIXED_NOW = datetime(2026, 11, 5, 12, 0, tzinfo=timezone.utc)


class FakeEventRepository:
    """Stands in for Datastore. Set `events` or `error` per test."""

    def __init__(self):
        self.events = []
        self.error = None
        self.calls = []

    def list_upcoming(self, now, limit):
        self.calls.append((now, limit))
        if self.error:
            raise self.error
        return self.events[:limit]


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


@pytest.fixture
def client(repository):
    app = create_app(EventService(repository, clock=lambda: FIXED_NOW))
    return app.test_client()
