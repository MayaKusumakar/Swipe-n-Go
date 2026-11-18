"""Private locations and host management are enforced by the server, not just the app.

The `client` fixture is signed in as the host (Avery); `as_user(name)` signs a
request in as someone else.
"""
import pytest

from conftest import HOST_NAME, as_user, user_id
from test_create_event_api import VALID_BODY


def create(client, **overrides):
    response = client.post("/api/events", json=VALID_BODY | overrides)
    assert response.status_code == 201
    return response.get_json()


def join(client, event_id, name="Maya"):
    response = client.post(f"/api/events/{event_id}/attendees", headers=as_user(name))
    assert response.status_code == 201
    return response.get_json()


def host():
    return as_user(HOST_NAME)


def guest(name="Maya"):
    return as_user(name)


@pytest.fixture
def private_event(client):
    return create(client, location_private=True)


def test_create_records_the_signed_in_host(client):
    created = create(client, host_name="Someone Else")
    assert created["host_id"] == user_id(HOST_NAME)
    assert created["host_name"] == HOST_NAME  # from the account, not the request
    assert "host_token" not in created


def test_private_location_is_hidden_from_the_public_list(client, private_event):
    assert private_event["location_name"] == "UC Davis Arboretum"  # the host sees it

    listed = client.get("/api/events").get_json()["events"][0]
    assert listed["location_private"] is True
    assert listed["location_name"] is None
    assert listed["address"] is None
    assert listed["latitude"] is None and listed["longitude"] is None


def test_private_location_forces_approval(client, private_event):
    assert private_event["requires_approval"] is True


def test_location_needs_host_or_approved_attendee(client, private_event):
    event_id = private_event["id"]
    attendee = join(client, event_id)
    assert attendee == {"id": user_id("Maya"), "name": "Maya", "status": "pending"}

    assert client.get(f"/api/events/{event_id}/location", headers=guest()).status_code == 403
    assert client.get(f"/api/events/{event_id}/location", headers=guest("Hana")).status_code == 403

    owner = client.get(f"/api/events/{event_id}/location", headers=host())
    assert owner.status_code == 200
    assert owner.get_json()["location_name"] == "UC Davis Arboretum"

    approved = client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve", headers=host())
    assert approved.get_json()["status"] == "approved"

    revealed = client.get(f"/api/events/{event_id}/location", headers=guest())
    assert revealed.status_code == 200
    assert revealed.get_json() == {
        "location_name": "UC Davis Arboretum", "address": "Garrod Dr, Davis, CA",
        "latitude": 38.5372, "longitude": -121.7531,
    }


def test_only_the_host_can_approve_or_list(client, private_event):
    event_id = private_event["id"]
    attendee = join(client, event_id)
    create(client)  # Avery hosting something else doesn't matter

    for headers in (guest(), guest("Hana")):
        assert client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve",
                           headers=headers).status_code == 403
        assert client.get(f"/api/events/{event_id}/attendees", headers=headers).status_code == 403

    listed = client.get(f"/api/events/{event_id}/attendees", headers=host())
    assert listed.get_json() == {"attendees": [{"id": user_id("Maya"), "name": "Maya", "status": "pending"}]}


def test_asking_twice_returns_the_same_entry(client, private_event):
    first = join(client, private_event["id"])
    again = client.post(f"/api/events/{private_event['id']}/attendees", headers=guest())
    assert again.status_code == 200
    assert again.get_json() == first


def test_host_cannot_join_their_own_event(client, private_event):
    response = client.post(f"/api/events/{private_event['id']}/attendees", headers=host())
    assert response.status_code == 403


def test_attendee_sees_their_own_status(client, private_event):
    event_id = private_event["id"]
    join(client, event_id)
    assert client.get(f"/api/events/{event_id}/attendees/me", headers=guest()).get_json()["status"] == "pending"
    client.post(f"/api/events/{event_id}/attendees/{user_id('Maya')}/approve", headers=host())
    assert client.get(f"/api/events/{event_id}/attendees/me", headers=guest()).get_json()["status"] == "approved"
    assert client.get(f"/api/events/{event_id}/attendees/me", headers=guest("Hana")).status_code == 404


def test_host_removes_attendee_and_they_lose_the_location(client, private_event):
    event_id = private_event["id"]
    attendee = join(client, event_id)
    client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve", headers=host())

    removed = client.delete(f"/api/events/{event_id}/attendees/{attendee['id']}", headers=host())
    assert removed.status_code == 204

    assert client.get(f"/api/events/{event_id}/location", headers=guest()).status_code == 403
    listed = client.get(f"/api/events/{event_id}/attendees", headers=host())
    assert listed.get_json() == {"attendees": []}


def test_attendee_can_only_remove_themselves(client, private_event):
    event_id = private_event["id"]
    maya = join(client, event_id, "Maya")
    hana = join(client, event_id, "Hana")

    assert client.delete(f"/api/events/{event_id}/attendees/{hana['id']}", headers=guest("Maya")).status_code == 403
    assert client.delete(f"/api/events/{event_id}/attendees/{maya['id']}", headers=guest("Maya")).status_code == 204


def test_public_event_join_is_approved_and_location_is_open(client):
    event = create(client)
    attendee = join(client, event["id"])
    assert attendee["status"] == "approved"
    assert client.get(f"/api/events/{event['id']}/location", headers=guest("Hana")).status_code == 200


def test_unknown_event_or_attendee_is_404(client, private_event):
    assert client.post("/api/events/nope/attendees", headers=guest()).status_code == 404
    assert client.get("/api/events/nope/location").status_code == 404
    assert client.delete(f"/api/events/{private_event['id']}/attendees/nope", headers=host()).status_code == 404


def test_location_private_must_be_boolean(client):
    response = client.post("/api/events", json=VALID_BODY | {"location_private": "yes"})
    assert response.status_code == 400
