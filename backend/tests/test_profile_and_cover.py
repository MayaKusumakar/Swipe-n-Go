import base64

import pytest

from conftest import FIXED_NOW, as_user, make_app, user_id
from repositories.memory_event_repository import InMemoryEventRepository
from repositories.user_repository import InMemoryUserRepository
from services.event_service import EventService
from test_create_event_api import VALID_BODY

JPEG = b"\xff\xd8\xff\xe0" + b"\x01" * 200


@pytest.fixture
def app():
    service = EventService(InMemoryEventRepository([]), clock=lambda: FIXED_NOW)
    users = InMemoryUserRepository()
    application = make_app(service)
    application.extensions["user_repository"] = users
    return application


def call(app, method, path, name="Avery", **kwargs):
    return getattr(app.test_client(), method)(path, headers=as_user(name), **kwargs)


def create_event(app, name="Avery"):
    response = call(app, "post", "/api/events", name=name, json=VALID_BODY)
    assert response.status_code == 201
    return response.get_json()


# MARK: Display name (the name from the app's profile)

def test_events_use_the_profile_name_once_set(app):
    assert create_event(app)["host_name"] == "Avery"            # sign-in name until changed

    response = call(app, "patch", "/api/auth/me", json={"name": "  AK  "})
    assert response.status_code == 200 and response.get_json()["name"] == "AK"

    assert create_event(app)["host_name"] == "AK"
    assert call(app, "get", "/api/auth/me").get_json()["name"] == "AK"


def test_join_requests_use_the_profile_name(app):
    event = create_event(app, name="Avery")
    call(app, "patch", "/api/auth/me", name="Blake", json={"name": "B. Lee"})
    call(app, "post", f"/api/events/{event['id']}/attendees", name="Blake")

    attendees = call(app, "get", f"/api/events/{event['id']}/attendees", name="Avery").get_json()["attendees"]
    assert [a["name"] for a in attendees] == ["B. Lee"]


def test_signing_in_again_keeps_the_profile_name(app):
    call(app, "patch", "/api/auth/me", json={"name": "AK"})
    call(app, "post", "/api/auth/sign-in")

    assert app.extensions["user_repository"].get(user_id("Avery")).display_name == "AK"
    assert create_event(app)["host_name"] == "AK"


@pytest.mark.parametrize("body", [{}, {"name": ""}, {"name": "   "}, {"name": 5}, {"name": "x" * 61}, []])
def test_rejects_bad_names(app, body):
    response = call(app, "patch", "/api/auth/me", json=body)
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_name"


# MARK: Cover photos

def put_cover(app, event_id, data=JPEG, name="Avery"):
    return call(app, "put", f"/api/events/{event_id}/cover", name=name,
                json={"image": base64.b64encode(data).decode()})


def test_host_uploads_cover_and_others_can_see_it(app):
    event = create_event(app)
    response = put_cover(app, event["id"])
    assert response.status_code == 200
    image_url = response.get_json()["image_url"]
    assert image_url.startswith(f"/api/events/{event['id']}/cover?v=")

    listed = call(app, "get", "/api/events", name="Blake").get_json()["events"]
    assert listed[0]["image_url"] == image_url

    cover = call(app, "get", f"/api/events/{event['id']}/cover", name="Blake")
    assert cover.status_code == 200
    assert cover.mimetype == "image/jpeg" and cover.data == JPEG


def test_new_cover_gets_a_new_version(app):
    event = create_event(app)
    first = put_cover(app, event["id"]).get_json()["image_url"]
    second = put_cover(app, event["id"], data=JPEG + b"\x02").get_json()["image_url"]
    assert first != second


def test_only_the_host_can_set_the_cover(app):
    event = create_event(app)
    assert put_cover(app, event["id"], name="Blake").status_code == 403


def test_cover_needs_sign_in(app):
    event = create_event(app)
    assert app.test_client().get(f"/api/events/{event['id']}/cover").status_code == 401


def test_missing_cover_and_event_are_404(app):
    event = create_event(app)
    assert call(app, "get", f"/api/events/{event['id']}/cover").status_code == 404
    assert put_cover(app, "no-such-event").status_code == 404


@pytest.mark.parametrize("data, message", [
    (b"\x89PNG\r\n\x1a\n" + b"\x00" * 10, "JPEG"),
    (b"\xff\xd8\xff" + b"\x00" * (900 * 1024), "900 KB"),
])
def test_rejects_bad_covers(app, data, message):
    event = create_event(app)
    response = put_cover(app, event["id"], data=data)
    assert response.status_code == 400 and message in response.get_json()["error"]["message"]


def test_rejects_non_base64_cover(app):
    event = create_event(app)
    response = call(app, "put", f"/api/events/{event['id']}/cover", json={"image": "%%%"})
    assert response.status_code == 400
