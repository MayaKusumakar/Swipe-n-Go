from datetime import timedelta

from conftest import FIXED_NOW, make_event
from main import create_app
from repositories.dev_sample_events import build_sample_events
from repositories.memory_event_repository import InMemoryEventRepository


def test_sample_events_are_upcoming_with_unique_ids():
    events = build_sample_events(FIXED_NOW)

    assert len(events) == 8
    assert len({e.id for e in events}) == 8
    assert all(e.start_time > FIXED_NOW for e in events)
    assert all(e.end_time > e.start_time for e in events)


def test_memory_repository_filters_past_sorts_and_limits():
    past = make_event("past", start_time=FIXED_NOW - timedelta(hours=1))
    later = make_event("later", start_time=FIXED_NOW + timedelta(days=2))
    sooner = make_event("sooner", start_time=FIXED_NOW + timedelta(days=1))
    repository = InMemoryEventRepository([later, past, sooner])

    assert [e.id for e in repository.list_upcoming(FIXED_NOW, 10)] == ["sooner", "later"]
    assert [e.id for e in repository.list_upcoming(FIXED_NOW, 1)] == ["sooner"]


def test_memory_event_store_serves_sample_events(monkeypatch):
    monkeypatch.setenv("EVENT_STORE", "memory")

    response = create_app().test_client().get("/api/events")

    assert response.status_code == 200
    body = response.get_json()
    assert body["count"] == 8
    starts = [e["start_time"] for e in body["events"]]
    assert starts == sorted(starts)
