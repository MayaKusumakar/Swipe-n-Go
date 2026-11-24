import pytest

from services.flyer_service import FlyerService
from services.instagram import normalize
from test_create_event_api import VALID_BODY, post
from test_flyers import body as flyer_body, flyer_client, output


@pytest.mark.parametrize("raw, handle", [
    ("@DavisClimbing", "davisclimbing"),
    ("davis.climbing_club", "davis.climbing_club"),
    ("  @ucd_aggies  ", "ucd_aggies"),
    ("https://www.instagram.com/davisclimbing/", "davisclimbing"),
    ("instagram.com/davisclimbing?hl=en", "davisclimbing"),
    ("http://instagr.am/davisclimbing", "davisclimbing"),
])
def test_accepts_handles_and_profile_links(raw, handle):
    assert normalize(raw) == handle


@pytest.mark.parametrize("raw", [
    "", "   ", None, "@", "two words", ".startsdot", "ends.", "dou..ble", "x" * 31, "bad!char",
    "https://www.instagram.com/p/Cx123/", "https://twitter.com/davisclimbing", "instagram.com/",
    "davisclimbing.com/about",
])
def test_rejects_anything_else(raw):
    assert normalize(raw) is None


def test_event_keeps_a_normalized_handle(client):
    response = post(client, VALID_BODY | {"instagram": "https://instagram.com/DavisClimbing/"})
    assert response.status_code == 201
    assert response.get_json()["instagram"] == "davisclimbing"
    listed = client.get("/api/events").get_json()["events"]
    assert listed[0]["instagram"] == "davisclimbing"


@pytest.mark.parametrize("value", [None, "", "  "])
def test_instagram_is_optional(client, value):
    body = VALID_BODY | ({"instagram": value} if value is not None else {})
    response = post(client, body)
    assert response.status_code == 201
    assert response.get_json()["instagram"] is None


@pytest.mark.parametrize("value", ["not a handle", 42, "https://instagram.com/p/abc/"])
def test_invalid_instagram_is_rejected(client, value):
    response = post(client, VALID_BODY | {"instagram": value})
    assert response.status_code == 400
    assert "instagram" in response.get_json()["error"]["message"]


def test_flyer_reader_returns_the_printed_handle(post_flyer):
    client, _ = flyer_client(output=output(instagram="Follow @DavisClimbing"))
    # Not a clean handle: dropped rather than guessed at.
    assert post_flyer(FlyerService(client=client), flyer_body()).get_json()["instagram"] is None

    client, _ = flyer_client(output=output(instagram="@DavisClimbing"))
    assert post_flyer(FlyerService(client=client), flyer_body()).get_json()["instagram"] == "davisclimbing"


@pytest.fixture
def post_flyer(repository):
    from conftest import make_app, signed_in
    from services.event_service import EventService

    def run(service, payload):
        app = make_app(EventService(repository), flyer_service=service)
        return signed_in(app).post("/api/flyers/read", json=payload)
    return run
