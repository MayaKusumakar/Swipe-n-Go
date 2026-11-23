"""DELETE /api/events/<id>: the host deletes a posted event (the app's "Delete plan")."""
from unittest.mock import MagicMock

from google.api_core.exceptions import ServiceUnavailable

from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository
from conftest import make_event
from test_attendees_api import create, guest, join


def test_host_deletes_their_event(client, repository):
    event = create(client)
    join(client, event["id"])

    response = client.delete(f"/api/events/{event['id']}")

    assert response.status_code == 204
    assert repository.events == []
    assert repository.attendees == {}
    assert client.get(f"/api/events/{event['id']}/attendees").status_code == 404


def test_only_the_host_can_delete(client, repository):
    event = create(client)
    response = client.delete(f"/api/events/{event['id']}", headers=guest())
    assert response.status_code == 403
    assert len(repository.events) == 1


def test_sample_events_without_a_host_cannot_be_deleted(client, repository):
    repository.events = [make_event()]
    assert client.delete("/api/events/seed-001").status_code == 403


def test_unknown_event_is_404(client):
    assert client.delete("/api/events/nope").status_code == 404


def test_store_down_is_503(client, repository):
    event = create(client)
    repository.error = ServiceUnavailable("down")
    assert client.delete(f"/api/events/{event['id']}").status_code == 503


def test_memory_store_deletes_attendees_and_cover():
    store = InMemoryEventRepository([make_event()])
    store.save_cover("seed-001", b"jpeg", "/cover")
    assert store.delete_event("seed-001") is True
    assert store.get("seed-001") is None and store.get_cover("seed-001") is None
    assert store.delete_event("seed-001") is False


def test_datastore_deletes_event_attendees_and_cover_together():
    client = MagicMock()
    client.key.side_effect = lambda *path: path
    attendee = MagicMock()
    attendee.key = ("Event", "e1", "Attendee", "maya")
    client.query.return_value.fetch.return_value = [attendee]

    assert EventRepository(client=client).delete_event("e1") is True

    client.delete_multi.assert_called_once_with([("Event", "e1", "Attendee", "maya"), ("Cover", "e1"), ("Event", "e1")])
    client.get.return_value = None
    assert EventRepository(client=client).delete_event("e1") is False
