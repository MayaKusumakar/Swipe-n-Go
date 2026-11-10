"""Private locations and host management are enforced by the server, not just the app."""
import pytest

from test_create_event_api import VALID_BODY


def create(client, **overrides):
    response = client.post("/api/events", json=VALID_BODY | overrides)
    assert response.status_code == 201
    return response.get_json()


def join(client, event_id, name="Maya"):
    response = client.post(f"/api/events/{event_id}/attendees", json={"name": name})
    assert response.status_code == 201
    return response.get_json()


def host(token):
    return {"X-Host-Token": token}


def guest(token):
    return {"X-Attendee-Token": token}


@pytest.fixture
def private_event(client):
    return create(client, location_private=True)


def test_create_returns_host_token_once(client):
    created = create(client)
    assert len(created["host_token"]) >= 32

    listed = client.get("/api/events").get_json()["events"][0]
    assert "host_token" not in listed
    assert "host_token_hash" not in listed


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
    assert attendee["status"] == "pending"

    assert client.get(f"/api/events/{event_id}/location").status_code == 403
    assert client.get(f"/api/events/{event_id}/location", headers=guest(attendee["attendee_token"])).status_code == 403
    assert client.get(f"/api/events/{event_id}/location", headers=guest("made-up")).status_code == 403

    owner = client.get(f"/api/events/{event_id}/location", headers=host(private_event["host_token"]))
    assert owner.status_code == 200
    assert owner.get_json()["location_name"] == "UC Davis Arboretum"

    approved = client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve",
                           headers=host(private_event["host_token"]))
    assert approved.get_json()["status"] == "approved"

    revealed = client.get(f"/api/events/{event_id}/location", headers=guest(attendee["attendee_token"]))
    assert revealed.status_code == 200
    assert revealed.get_json() == {
        "location_name": "UC Davis Arboretum", "address": "Garrod Dr, Davis, CA",
        "latitude": 38.5372, "longitude": -121.7531,
    }


def test_only_the_host_can_approve_or_list(client, private_event):
    event_id = private_event["id"]
    attendee = join(client, event_id)
    other_host = create(client)["host_token"]  # a host of a different event

    for headers in ({}, guest(attendee["attendee_token"]), host(other_host)):
        assert client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve",
                           headers=headers).status_code == 403
        assert client.get(f"/api/events/{event_id}/attendees", headers=headers).status_code == 403

    listed = client.get(f"/api/events/{event_id}/attendees", headers=host(private_event["host_token"]))
    assert listed.get_json() == {"attendees": [{"id": attendee["id"], "name": "Maya", "status": "pending"}]}


def test_host_removes_attendee_and_they_lose_the_location(client, private_event):
    event_id = private_event["id"]
    attendee = join(client, event_id)
    client.post(f"/api/events/{event_id}/attendees/{attendee['id']}/approve", headers=host(private_event["host_token"]))

    removed = client.delete(f"/api/events/{event_id}/attendees/{attendee['id']}", headers=host(private_event["host_token"]))
    assert removed.status_code == 204

    assert client.get(f"/api/events/{event_id}/location", headers=guest(attendee["attendee_token"])).status_code == 403
    listed = client.get(f"/api/events/{event_id}/attendees", headers=host(private_event["host_token"]))
    assert listed.get_json() == {"attendees": []}


def test_attendee_can_only_remove_themselves(client, private_event):
    event_id = private_event["id"]
    maya = join(client, event_id, "Maya")
    hana = join(client, event_id, "Hana")

    assert client.delete(f"/api/events/{event_id}/attendees/{hana['id']}",
                         headers=guest(maya["attendee_token"])).status_code == 403
    assert client.delete(f"/api/events/{event_id}/attendees/{hana['id']}").status_code == 403
    assert client.delete(f"/api/events/{event_id}/attendees/{maya['id']}",
                         headers=guest(maya["attendee_token"])).status_code == 204


def test_public_event_join_is_approved_and_location_is_open(client):
    event = create(client)
    attendee = join(client, event["id"])
    assert attendee["status"] == "approved"
    assert client.get(f"/api/events/{event['id']}/location").status_code == 200


def test_unknown_event_or_attendee_is_404(client, private_event):
    assert client.post("/api/events/nope/attendees", json={"name": "Maya"}).status_code == 404
    assert client.get("/api/events/nope/location").status_code == 404
    assert client.delete(f"/api/events/{private_event['id']}/attendees/nope",
                         headers=host(private_event["host_token"])).status_code == 404


def test_join_needs_a_name(client, private_event):
    response = client.post(f"/api/events/{private_event['id']}/attendees", json={"name": "  "})
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_attendee"


def test_location_private_must_be_boolean(client):
    response = client.post("/api/events", json=VALID_BODY | {"location_private": "yes"})
    assert response.status_code == 400
