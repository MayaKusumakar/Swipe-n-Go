import uuid

import pytest
from google.api_core.exceptions import ServiceUnavailable

from conftest import make_event

VALID_BODY = {
    "title": "Sunrise Arboretum 5K",
    "description": "Easy pace, coffee after.",
    "start_time": "2026-11-06T14:30:00+00:00",
    "end_time": "2026-11-06T15:15:00+00:00",
    "location_name": "UC Davis Arboretum",
    "latitude": 38.5372,
    "longitude": -121.7531,
    "category": "run",
    "host_name": "Anant Katiyar",
    "address": "Garrod Dr, Davis, CA",
    "capacity": 6,
    "cost": "Free",
    "tags": ["Running", "Coffee after"],
    "level": "beginner",
    "requires_approval": False,
}


def post(client, body):
    return client.post("/api/events", json=body)


def test_creates_event_and_returns_it(client, repository):
    response = post(client, VALID_BODY)

    assert response.status_code == 201
    body = response.get_json()
    uuid.UUID(body["id"])  # server-generated UUID
    assert body["title"] == "Sunrise Arboretum 5K"
    assert body["start_time"] == "2026-11-06T14:30:00+00:00"
    assert body["host_name"] == "Avery"  # the signed-in host, not the request body
    assert body["capacity"] == 6
    assert body["tags"] == ["Running", "Coffee after"]
    assert body["attendee_count"] == 0
    assert [e.id for e in repository.events] == [body["id"]]


def test_created_event_is_listed(client):
    created = post(client, VALID_BODY).get_json()

    listed = client.get("/api/events").get_json()

    assert [e["id"] for e in listed["events"]] == [created["id"]]


def test_only_required_fields(client):
    body = {k: VALID_BODY[k] for k in ("title", "start_time", "location_name", "category")}

    response = post(client, body)

    assert response.status_code == 201
    created = response.get_json()
    assert created["description"] == ""
    assert created["end_time"] is None
    assert created["latitude"] is None
    assert created["tags"] == []
    assert created["requires_approval"] is False


def test_uses_client_supplied_uuid(client):
    event_id = "6f1c2a3e-1b2c-4d5e-8f90-123456789abc"

    response = post(client, {**VALID_BODY, "id": event_id.upper()})

    assert response.status_code == 201
    assert response.get_json()["id"] == event_id


def test_duplicate_id_returns_409(client, repository):
    event_id = "6f1c2a3e-1b2c-4d5e-8f90-123456789abc"
    repository.events = [make_event(event_id)]

    response = post(client, {**VALID_BODY, "id": event_id})

    assert response.status_code == 409
    assert response.get_json()["error"]["code"] == "event_exists"


def test_trims_text(client):
    response = post(client, {**VALID_BODY, "title": "  Taco crawl  "})

    assert response.get_json()["title"] == "Taco crawl"


@pytest.mark.parametrize("change, field", [
    ({"title": None}, "title"),
    ({"title": "   "}, "title"),
    ({"title": "x" * 121}, "title"),
    ({"title": 5}, "title"),
    ({"start_time": None}, "start_time"),
    ({"start_time": "tomorrow"}, "start_time"),
    ({"start_time": "2026-11-06T14:30:00"}, "start_time"),           # no UTC offset
    ({"start_time": "2026-11-04T14:30:00+00:00"}, "start_time"),     # in the past
    ({"end_time": "2026-11-06T14:00:00+00:00"}, "end_time"),         # before start
    ({"location_name": ""}, "location_name"),
    ({"category": "Running"}, "category"),
    ({"category": None}, "category"),
    ({"latitude": 91}, "latitude"),
    ({"latitude": True}, "latitude"),
    ({"longitude": None}, "latitude"),                                 # must come in pairs
    ({"capacity": 1}, "capacity"),
    ({"capacity": "6"}, "capacity"),
    ({"tags": "Running"}, "tags"),
    ({"tags": ["x" * 31]}, "tags"),
    ({"tags": ["t"] * 11}, "tags"),
    ({"level": "expert"}, "level"),
    ({"requires_approval": "yes"}, "requires_approval"),
    ({"id": "not-a-uuid"}, "id"),
])
def test_rejects_invalid_fields(client, repository, change, field):
    body = {**VALID_BODY, **change}

    response = post(client, body)

    assert response.status_code == 400
    error = response.get_json()["error"]
    assert error["code"] == "invalid_event"
    assert field in error["message"]
    assert repository.events == []


@pytest.mark.parametrize("raw", ["not json", "[1, 2]", ""])
def test_rejects_non_object_body(client, raw):
    response = client.post("/api/events", data=raw, content_type="application/json")

    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_event"


def test_datastore_failure_returns_503(client, repository):
    repository.error = ServiceUnavailable("datastore down")

    response = post(client, VALID_BODY)

    assert response.status_code == 503
    assert response.get_json()["error"]["code"] == "datastore_unavailable"
