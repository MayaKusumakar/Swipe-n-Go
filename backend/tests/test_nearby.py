"""Geohash nearby search: GET /api/events/nearby."""
import math
import random
from datetime import timedelta
from unittest.mock import MagicMock

import pytest

from conftest import FIXED_NOW, make_event
from repositories.event_repository import EventRepository
from services import geo

DAVIS = (38.5382, -121.7617)
SACRAMENTO = (38.5816, -121.4944)  # about 14.6 miles from Davis


def test_encode_matches_the_reference_example():
    # The standard example from the geohash spec.
    assert geo.encode(57.64911, 10.40744, 11) == "u4pruydqqvj"


def test_distance():
    assert geo.distance_km(0, 0, 1, 0) == pytest.approx(111.2, abs=0.1)
    miles = geo.distance_km(*DAVIS, *SACRAMENTO) / geo.KM_PER_MILE
    assert 14 < miles < 15.5


@pytest.mark.parametrize("radius_km", [0.5, 3, 8.05, 20, 40])
def test_covering_cells_contain_every_point_in_the_circle(radius_km):
    cells = geo.covering_cells(*DAVIS, radius_km)
    rng = random.Random(7)
    for _ in range(500):
        # A random point within radius_km of Davis.
        bearing, dist = rng.uniform(0, 2 * math.pi), radius_km * math.sqrt(rng.random())
        lat = DAVIS[0] + dist / geo.KM_PER_DEGREE * math.cos(bearing)
        lng = DAVIS[1] + dist / (geo.KM_PER_DEGREE * math.cos(math.radians(DAVIS[0]))) * math.sin(bearing)
        if geo.distance_km(*DAVIS, lat, lng) <= radius_km:
            assert geo.encode(lat, lng).startswith(tuple(cells))


def test_five_miles_in_davis_uses_nine_cells_at_most():
    assert len(geo.covering_cells(*DAVIS, 5 * geo.KM_PER_MILE)) <= 9


def at(hours):
    return FIXED_NOW + timedelta(hours=hours)


def nearby(client, **params):
    return client.get("/api/events/nearby", query_string={"lat": DAVIS[0], "lng": DAVIS[1]} | params)


def test_returns_close_upcoming_public_events_soonest_first(client, repository):
    repository.events = [
        make_event("later", latitude=38.5424, longitude=-121.7494, start_time=at(5)),
        make_event("sooner", latitude=38.5430, longitude=-121.7590, start_time=at(2)),
        make_event("sacramento", latitude=SACRAMENTO[0], longitude=SACRAMENTO[1], start_time=at(1)),
        make_event("past", latitude=38.5424, longitude=-121.7494, start_time=at(-1)),
        make_event("private", latitude=38.5424, longitude=-121.7494, start_time=at(1), location_private=True),
        make_event("no-place", latitude=None, longitude=None, start_time=at(1)),
    ]

    response = nearby(client)

    assert response.status_code == 200
    body = response.get_json()
    assert [e["id"] for e in body["events"]] == ["sooner", "later"]
    assert body["count"] == 2
    assert 0 < body["events"][0]["distance_miles"] < 1


def test_bigger_radius_reaches_sacramento(client, repository):
    repository.events = [make_event("sacramento", latitude=SACRAMENTO[0], longitude=SACRAMENTO[1], start_time=at(1))]
    assert nearby(client, radius_miles=20).get_json()["count"] == 1


def test_limit(client, repository):
    repository.events = [make_event(f"e{i}", latitude=38.54, longitude=-121.75, start_time=at(i + 1)) for i in range(5)]
    assert nearby(client, limit=2).get_json()["count"] == 2


@pytest.mark.parametrize("params", [
    {"lat": None}, {"lat": "abc"}, {"lat": "91"}, {"lng": "-181"}, {"lat": "nan"},
    {"radius_miles": "0"}, {"radius_miles": "26"}, {"limit": "0"},
])
def test_rejects_bad_parameters(client, params):
    query = {"lat": DAVIS[0], "lng": DAVIS[1]} | params
    response = client.get("/api/events/nearby", query_string={k: v for k, v in query.items() if v is not None})
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_parameter"


def test_datastore_failure_is_503(client, repository):
    from google.api_core.exceptions import ServiceUnavailable
    repository.error = ServiceUnavailable("down")
    assert nearby(client).status_code == 503


def test_datastore_runs_one_prefix_range_query_per_cell():
    client = MagicMock()
    client.query.return_value.fetch.return_value = []

    EventRepository(client=client).list_in_geohash_cells(["9qce", "9qcs"])

    filters = [c.kwargs["filter"] for c in client.query.return_value.add_filter.call_args_list]
    assert [(f.property_name, f.operator, f.value) for f in filters] == [
        ("geohash", ">=", "9qce"), ("geohash", "<", "9qce~"),
        ("geohash", ">=", "9qcs"), ("geohash", "<", "9qcs~"),
    ]


def test_events_store_their_geohash():
    props = make_event(latitude=DAVIS[0], longitude=DAVIS[1]).to_entity_properties()
    assert props["geohash"] == geo.encode(*DAVIS)
    assert make_event(latitude=None, longitude=None).to_entity_properties()["geohash"] is None
