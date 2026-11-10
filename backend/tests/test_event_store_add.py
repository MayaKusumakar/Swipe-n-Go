from datetime import timedelta
from unittest.mock import MagicMock

from conftest import FIXED_NOW, make_event
from models import EVENT_KIND
from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository


def test_datastore_add_stores_all_fields():
    client = MagicMock()
    client.get.return_value = None
    event = make_event("abc", host_name="Maya", capacity=6, tags=["Running"], level="beginner")

    assert EventRepository(client=client).add(event) is True

    client.key.assert_called_once_with(EVENT_KIND, "abc")
    stored = client.put.call_args.args[0]
    assert stored["title"] == "Trivia Night"
    assert stored["host_name"] == "Maya"
    assert stored["capacity"] == 6
    assert stored["tags"] == ["Running"]
    assert stored["level"] == "beginner"


def test_datastore_add_refuses_existing_id():
    client = MagicMock()
    client.get.return_value = object()

    assert EventRepository(client=client).add(make_event("abc")) is False
    client.put.assert_not_called()


def test_memory_store_add_then_list_in_order():
    later = make_event("later", start_time=FIXED_NOW + timedelta(days=2))
    store = InMemoryEventRepository([later])

    assert store.add(make_event("sooner", start_time=FIXED_NOW + timedelta(days=1))) is True
    assert store.add(make_event("sooner")) is False

    assert [e.id for e in store.list_upcoming(FIXED_NOW, 10)] == ["sooner", "later"]
