import pytest
from google.api_core.exceptions import ServiceUnavailable
from google.auth.exceptions import DefaultCredentialsError

from conftest import FIXED_NOW, make_event

EVENT_FIELDS = {
    "id", "title", "description", "start_time", "end_time", "location_name",
    "latitude", "longitude", "category", "image_url",
    "host_name", "address", "capacity", "attendee_count", "cost", "tags",
    "level", "requires_approval", "location_private",
}


def test_returns_events_with_expected_shape(client, repository):
    repository.events = [make_event("seed-001"), make_event("seed-002", end_time=None)]

    response = client.get("/api/events")

    assert response.status_code == 200
    body = response.get_json()
    assert body["count"] == 2
    assert [e["id"] for e in body["events"]] == ["seed-001", "seed-002"]
    first = body["events"][0]
    assert set(first) == EVENT_FIELDS
    assert first["start_time"] == "2026-11-06T19:00:00+00:00"
    assert first["latitude"] == 38.5424
    assert body["events"][1]["end_time"] is None


def test_empty_collection_returns_empty_list(client, repository):
    response = client.get("/api/events")

    assert response.status_code == 200
    assert response.get_json() == {"events": [], "count": 0}


def test_uses_default_limit_and_current_time(client, repository):
    client.get("/api/events")

    assert repository.calls == [(FIXED_NOW, 20)]


def test_passes_limit_through(client, repository):
    repository.events = [make_event(f"seed-{i}") for i in range(5)]

    response = client.get("/api/events?limit=3")

    assert response.get_json()["count"] == 3
    assert repository.calls[0][1] == 3


@pytest.mark.parametrize("limit", ["1", "50"])
def test_accepts_limit_bounds(client, limit):
    assert client.get(f"/api/events?limit={limit}").status_code == 200


@pytest.mark.parametrize("limit", ["0", "-1", "51", "abc", "2.5", "", "²"])
def test_rejects_invalid_limit(client, repository, limit):
    response = client.get("/api/events", query_string={"limit": limit})

    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_parameter"
    assert repository.calls == []


@pytest.mark.parametrize("error", [
    ServiceUnavailable("datastore down"),
    DefaultCredentialsError("no credentials"),
    OSError("Project was not passed and could not be determined"),
])
def test_datastore_failure_returns_503(client, repository, error):
    repository.error = error

    response = client.get("/api/events")

    assert response.status_code == 503
    assert response.get_json() == {
        "error": {
            "code": "datastore_unavailable",
            "message": "Events are temporarily unavailable",
        }
    }
