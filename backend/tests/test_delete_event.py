"""DELETE /api/events/<id>: the host deletes a posted event (the app's "Delete plan")."""
from datetime import timedelta
from unittest.mock import MagicMock

from google.api_core.exceptions import ServiceUnavailable

from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository
from conftest import FIXED_NOW, make_event
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
    assert store.delete_event("seed-001", FIXED_NOW) is not None
    assert store.get("seed-001") is None and store.get_cover("seed-001") is None
    assert store.delete_event("seed-001", FIXED_NOW) is None


def test_datastore_deletes_event_attendees_and_cover_and_leaves_a_notice():
    client = MagicMock()

    def key(*path):
        k = MagicMock(id_or_name=path[-1])
        k.path = path
        return k
    client.key.side_effect = key
    attendee = MagicMock()
    attendee.key = key("Event", "e1", "Attendee", "maya")
    client.query.return_value.fetch.return_value = [attendee]
    event = {"title": "Trivia", "start_time": FIXED_NOW, "host_name": "Avery"}
    client.get.return_value = MagicMock(key=key("Event", "e1"), get=lambda k, d=None: event.get(k, d),
                                        __getitem__=lambda self, k: event[k])

    cancellation = EventRepository(client=client).delete_event("e1", FIXED_NOW)

    assert cancellation.attendee_ids == ["maya"] and cancellation.title == "Trivia"
    notice = client.put.call_args.args[0]
    assert notice["attendee_ids"] == ["maya"] and notice["cancelled_at"] == FIXED_NOW
    deleted = [k.path for k in client.delete_multi.call_args.args[0]]
    assert deleted == [("Event", "e1", "Attendee", "maya"), ("Cover", "e1"), ("Event", "e1")]

    client.get.return_value = None
    assert EventRepository(client=client).delete_event("e1", FIXED_NOW) is None


# Guests find out: GET /api/events/cancelled.

def test_guests_and_requesters_are_told_when_the_host_deletes(client):
    event = create(client, title="Pickup Soccer")
    join(client, event["id"], name="Maya")
    join(client, event["id"], name="Sam")
    assert client.delete(f"/api/events/{event['id']}").status_code == 204

    for name in ("Maya", "Sam"):
        cancelled = client.get("/api/events/cancelled", headers=guest(name)).get_json()["events"]
        assert cancelled == [{
            "event_id": event["id"], "title": "Pickup Soccer", "host_name": "Avery",
            "start_time": event["start_time"], "cancelled_at": FIXED_NOW.isoformat(),
        }]


def test_others_are_not_told_and_the_guest_list_stays_private(client):
    event = create(client)
    join(client, event["id"], name="Maya")
    client.delete(f"/api/events/{event['id']}")

    assert client.get("/api/events/cancelled", headers=guest("Stranger")).get_json()["events"] == []
    assert client.get("/api/events/cancelled").get_json()["events"] == []      # the host
    body = client.get("/api/events/cancelled", headers=guest("Maya")).get_json()
    assert "attendee_ids" not in body["events"][0]


def test_an_event_nobody_joined_leaves_nothing_behind(client, repository):
    event = create(client)
    client.delete(f"/api/events/{event['id']}")
    assert repository.cancellations == {}


def test_newest_cancellation_first(client, repository):
    first = create(client, title="First")
    second = create(client, title="Second")
    for e in (first, second):
        join(client, e["id"], name="Maya")
    client.delete(f"/api/events/{first['id']}")
    repository.cancellations[first["id"]].cancelled_at = FIXED_NOW - timedelta(hours=1)
    client.delete(f"/api/events/{second['id']}")

    titles = [c["title"] for c in client.get("/api/events/cancelled", headers=guest("Maya")).get_json()["events"]]
    assert titles == ["Second", "First"]


def test_cancelled_list_store_down_is_503(client, repository):
    repository.error = ServiceUnavailable("down")
    assert client.get("/api/events/cancelled", headers=guest("Maya")).status_code == 503
