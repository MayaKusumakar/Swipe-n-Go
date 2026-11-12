from conftest import FIXED_NOW, as_user, make_app
import pytest

from repositories.memory_event_repository import InMemoryEventRepository
from services.event_service import EventService
from test_create_event_api import VALID_BODY


@pytest.fixture
def app():
    return make_app(EventService(InMemoryEventRepository([]), clock=lambda: FIXED_NOW))


def call(app, method, path, name="Avery", **kwargs):
    return getattr(app.test_client(), method)(path, headers=as_user(name), **kwargs)


def create_event(app, name="Avery"):
    response = call(app, "post", "/api/events", name=name, json=VALID_BODY)
    assert response.status_code == 201
    return response.get_json()


# MARK: Saved events

def test_saved_events_follow_the_account(app):
    event = create_event(app, name="Blake")
    assert call(app, "get", "/api/me/saved").get_json() == {"event_ids": []}

    assert call(app, "put", f"/api/me/saved/{event['id']}").status_code == 200
    assert call(app, "put", f"/api/me/saved/{event['id']}").status_code == 200   # saving twice is fine
    # Another device signed in to the same account sees the same list.
    assert call(app, "get", "/api/me/saved").get_json() == {"event_ids": [event["id"]]}
    # Other people's lists are separate.
    assert call(app, "get", "/api/me/saved", name="Casey").get_json() == {"event_ids": []}

    assert call(app, "delete", f"/api/me/saved/{event['id']}").get_json() == {"event_ids": []}
    assert call(app, "delete", f"/api/me/saved/{event['id']}").status_code == 200  # already gone is fine


def test_saving_a_missing_event_is_404(app):
    assert call(app, "put", "/api/me/saved/no-such-event").status_code == 404


def test_signing_in_again_keeps_saved_events(app):
    event = create_event(app, name="Blake")
    call(app, "put", f"/api/me/saved/{event['id']}")
    call(app, "post", "/api/auth/sign-in")
    assert call(app, "get", "/api/me/saved").get_json() == {"event_ids": [event["id"]]}


def test_saved_needs_sign_in(app):
    assert app.test_client().get("/api/me/saved").status_code == 401


# MARK: Renaming

def test_renaming_updates_events_posted_earlier(app):
    first = create_event(app)
    other = create_event(app, name="Blake")
    assert first["host_name"] == "Avery"

    call(app, "patch", "/api/auth/me", json={"name": "AK"})

    events = {e["id"]: e for e in call(app, "get", "/api/events", name="Casey").get_json()["events"]}
    assert events[first["id"]]["host_name"] == "AK"
    assert events[other["id"]]["host_name"] == "Blake"


def test_me_says_whether_a_profile_name_was_chosen(app):
    assert call(app, "get", "/api/auth/me").get_json()["display_name"] is None
    call(app, "patch", "/api/auth/me", json={"name": "AK"})
    me = call(app, "get", "/api/auth/me").get_json()
    assert me["name"] == "AK" and me["display_name"] == "AK"
