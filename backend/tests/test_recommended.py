"""Free local interest matching: GET /api/events/recommended."""
from datetime import timedelta

import pytest

from conftest import FIXED_NOW, make_event
from services import matching


def at(hours):
    return FIXED_NOW + timedelta(hours=hours)


def score(interests, **event):
    return matching.similarity(matching.vectorize(interests),
                               matching.vectorize(matching.event_text(make_event(**event))))


def test_related_words_match_without_sharing_a_word():
    walk = score("hiking and backpacking", title="Arboretum Sunset Walk", category="outdoors",
                 description="Easy 2-mile walk, meet at the gazebo.")
    assert walk > 0.3


def test_unrelated_events_score_zero():
    assert score("hiking", title="Board Game Night", category="social",
                 description="Games provided, snacks welcome.", tags=[]) == 0


def test_closer_match_ranks_first():
    events = [
        (make_event("games", title="Board Game Night", category="games", description="", start_time=at(1)), None),
        (make_event("run", title="Sunrise 5K", category="run", description="Easy pace.", start_time=at(3)), None),
        (make_event("walk", title="Nature Walk", category="outdoors", description="", start_time=at(2)), None),
    ]
    ranked = matching.rank(["running"], events)
    assert [e.id for e, _, _ in ranked][0] == "run"
    assert "games" not in [e.id for e, _, _ in ranked]


def test_recommended_api_ranks_upcoming_events(client, repository):
    repository.events = [
        make_event("trivia", title="Trivia Night", category="games", description="Teams of up to 6.", start_time=at(1)),
        make_event("walk", title="Arboretum Sunset Walk", category="outdoors",
                   description="Easy 2-mile walk.", start_time=at(2)),
    ]

    response = client.get("/api/events/recommended", query_string={"interests": "hiking, backpacking"})

    assert response.status_code == 200
    body = response.get_json()
    assert [e["id"] for e in body["events"]] == ["walk"]
    assert body["events"][0]["match_score"] > 0
    assert body["events"][0]["distance_miles"] is None


def test_recommended_with_location_uses_nearby_events_only(client, repository):
    repository.events = [
        make_event("near", title="Pickup Soccer", category="sports", latitude=38.543, longitude=-121.759, start_time=at(1)),
        make_event("far", title="Pickup Soccer", category="sports", latitude=38.58, longitude=-121.49, start_time=at(1)),
    ]

    body = client.get("/api/events/recommended", query_string={
        "interests": "sports", "lat": 38.5382, "lng": -121.7617, "radius_miles": 3,
    }).get_json()

    assert [e["id"] for e in body["events"]] == ["near"]
    assert body["events"][0]["distance_miles"] < 3


@pytest.mark.parametrize("query", [
    {}, {"interests": " , "}, {"interests": ",".join(["a"] * 16)}, {"interests": "x" * 31},
    {"interests": "run", "lat": "38.5"}, {"interests": "run", "limit": "51"},
])
def test_rejects_bad_parameters(client, query):
    response = client.get("/api/events/recommended", query_string=query)
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_parameter"
