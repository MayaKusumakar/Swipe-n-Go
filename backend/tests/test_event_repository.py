from datetime import datetime, timezone
from unittest.mock import MagicMock

from google.cloud import datastore

from conftest import FIXED_NOW
from models import EVENT_KIND
from repositories.event_repository import EventRepository


def make_entity(name, **props):
    entity = datastore.Entity(key=datastore.Key(EVENT_KIND, name, project="test"))
    entity.update(props)
    return entity


def test_list_upcoming_queries_future_events_in_order():
    start = datetime(2026, 11, 6, 19, 0, tzinfo=timezone.utc)
    client = MagicMock()
    query = client.query.return_value
    query.fetch.return_value = [make_entity(
        "seed-001", title="Trivia Night", description="Teams of up to 6.",
        start_time=start, location_name="Memorial Union",
        latitude=38.5424, longitude=-121.7494, category="social",
    )]

    events = EventRepository(client=client).list_upcoming(FIXED_NOW, 10)

    client.query.assert_called_once_with(kind=EVENT_KIND)
    prop_filter = query.add_filter.call_args.kwargs["filter"]
    assert (prop_filter.property_name, prop_filter.operator, prop_filter.value) == (
        "start_time", ">=", FIXED_NOW,
    )
    assert query.order == ["start_time"]
    query.fetch.assert_called_once_with(limit=10)

    assert len(events) == 1
    event = events[0]
    assert event.id == "seed-001"
    assert event.title == "Trivia Night"
    assert event.start_time == start
    assert event.end_time is None
    assert event.image_url is None
