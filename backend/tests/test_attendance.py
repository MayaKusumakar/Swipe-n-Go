"""attendee_count is kept on the event (Datastore has no joins) and enforces capacity."""
from unittest.mock import MagicMock

from google.cloud import datastore

from conftest import as_user, make_event
from models import APPROVED, EVENT_KIND, Attendee
from repositories.event_repository import EventRepository
from test_attendees_api import create, guest, host, join
from test_create_event_api import VALID_BODY


def count(client, event_id):
    events = client.get("/api/events").get_json()["events"]
    return next(e for e in events if e["id"] == event_id)["attendee_count"]


def test_open_event_join_counts_at_once(client):
    event = create(client)
    join(client, event["id"])
    join(client, event["id"], "Hana")
    assert count(client, event["id"]) == 2


def test_request_counts_only_once_approved(client):
    event = create(client, requires_approval=True)
    attendee = join(client, event["id"])
    assert count(client, event["id"]) == 0

    url = f"/api/events/{event['id']}/attendees/{attendee['id']}/approve"
    client.post(url, headers=host())
    client.post(url, headers=host())  # approving twice changes nothing
    assert count(client, event["id"]) == 1


def test_removing_lowers_the_count_but_declining_a_request_does_not(client):
    event = create(client, requires_approval=True)
    maya, hana = join(client, event["id"]), join(client, event["id"], "Hana")
    client.post(f"/api/events/{event['id']}/attendees/{maya['id']}/approve", headers=host())

    client.delete(f"/api/events/{event['id']}/attendees/{hana['id']}", headers=host())
    assert count(client, event["id"]) == 1
    client.delete(f"/api/events/{event['id']}/attendees/{maya['id']}", headers=guest("Maya"))
    assert count(client, event["id"]) == 0


def test_full_event_refuses_joins(client):
    event = create(client, capacity=2)  # the host plus one
    join(client, event["id"])

    response = client.post(f"/api/events/{event['id']}/attendees", headers=as_user("Hana"))

    assert response.status_code == 409
    assert response.get_json()["error"]["code"] == "event_full"
    assert count(client, event["id"]) == 1


def test_full_event_refuses_approval_but_keeps_the_request(client):
    event = create(client, capacity=2, requires_approval=True)
    maya, hana = join(client, event["id"]), join(client, event["id"], "Hana")
    approve = f"/api/events/{event['id']}/attendees/%s/approve"
    assert client.post(approve % maya["id"], headers=host()).status_code == 200

    assert client.post(approve % hana["id"], headers=host()).status_code == 409
    listed = client.get(f"/api/events/{event['id']}/attendees", headers=host()).get_json()
    assert [(a["name"], a["status"]) for a in listed["attendees"]] == [("Maya", "approved"), ("Hana", "pending")]


def test_attendance_changes_mark_the_summary_stale(client, repository):
    event = create(client)
    repository.get(event["id"]).summary_stale = False
    join(client, event["id"])
    assert repository.get(event["id"]).summary_stale is True


def test_new_events_need_a_summary(client, repository):
    event = create(client)
    assert repository.get(event["id"]).summary_stale is True


# Datastore: the count and the attendee are written in one transaction.

def _entity(**props):
    entity = datastore.Entity(key=datastore.Key(EVENT_KIND, "e1", project="test"))
    entity.update(make_event("e1").to_entity_properties() | props)
    return entity


def _attendee():
    return Attendee(id="a1", event_id="e1", name="Maya", status=APPROVED, created_at=make_event().start_time)


def test_datastore_update_attendance_writes_both():
    client = MagicMock()
    stored = _entity(attendee_count=1, capacity=6)
    client.get.return_value = stored

    assert EventRepository(client=client).update_attendance("e1", _attendee(), +1) is True

    client.transaction.assert_called_once()
    assert stored["attendee_count"] == 2
    assert stored["summary_stale"] is True
    assert client.put.call_count == 2  # the event and the attendee


def test_datastore_update_attendance_refuses_when_full():
    client = MagicMock()
    client.get.return_value = _entity(attendee_count=5, capacity=6)

    assert EventRepository(client=client).update_attendance("e1", _attendee(), +1) is False
    client.put.assert_not_called()


def test_datastore_update_attendance_missing_event():
    client = MagicMock()
    client.get.return_value = None
    assert EventRepository(client=client).update_attendance("e1", _attendee(), +1) is None


def test_valid_body_has_capacity():
    # The capacity tests above rely on VALID_BODY being an open event.
    assert VALID_BODY["requires_approval"] is False
