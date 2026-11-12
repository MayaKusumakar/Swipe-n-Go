import base64
from types import SimpleNamespace

import pytest

from conftest import make_app, signed_in
from services.event_service import EventService
from services.flyer_service import FlyerService, _FlyerOutput

JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 64
PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 64
NOW = "2026-11-12T10:00:00-08:00"


class FakeMessages:
    def __init__(self, output=None, stop_reason="end_turn", error=None):
        self.output, self.stop_reason, self.error, self.calls = output, stop_reason, error, []

    def parse(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return SimpleNamespace(parsed_output=self.output, stop_reason=self.stop_reason)


def flyer_client(**kwargs):
    messages = FakeMessages(**kwargs)
    return SimpleNamespace(beta=SimpleNamespace(messages=messages)), messages


def output(**overrides):
    fields = dict(
        is_event_flyer=True, title="Fall Climbing Social", start_time="2026-11-14T19:00:00-08:00",
        end_time="2026-11-14T21:00:00-08:00", location_name="ARC Climbing Wall", address="ARC, UC Davis",
        description="Beginner-friendly climbing night with free gear rental.", cost="Free",
        category="sports", missing=[],
    )
    fields.update(overrides)
    return _FlyerOutput(**fields)


def body(raw=JPEG, media_type="image/jpeg", **overrides):
    payload = {"image": base64.b64encode(raw).decode(), "media_type": media_type, "now": NOW,
               "ocr_text": "FALL CLIMBING SOCIAL\nTHURS 11/14 7-9PM\nARC CLIMBING WALL\nFREE"}
    payload.update(overrides)
    return payload


@pytest.fixture
def post(repository):
    def run(service, payload):
        app = make_app(EventService(repository), flyer_service=service)
        return signed_in(app).post("/api/flyers/read", json=payload)
    return run


def test_reads_flyer_with_claude(post):
    client, messages = flyer_client(output=output())
    response = post(FlyerService(client=client), body())

    assert response.status_code == 200
    data = response.get_json()
    assert data["title"] == "Fall Climbing Social"
    assert data["start_time"] == "2026-11-14T19:00:00-08:00"
    assert data["end_time"] == "2026-11-14T21:00:00-08:00"
    assert data["category"] == "sports"
    assert data["missing"] == []

    call = messages.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert call["output_format"] is _FlyerOutput
    image_block, text_block = call["messages"][0]["content"]
    assert image_block["type"] == "image" and image_block["source"]["media_type"] == "image/jpeg"
    assert base64.b64decode(image_block["source"]["data"]) == JPEG
    assert "2026-11-12T10:00:00-08:00 (Thursday)" in text_block["text"]
    assert "FALL CLIMBING SOCIAL" in text_block["text"]


def test_png_is_accepted(post):
    client, _ = flyer_client(output=output())
    assert post(FlyerService(client=client), body(raw=PNG, media_type="image/png")).status_code == 200


def test_not_a_flyer(post):
    client, _ = flyer_client(output=output(is_event_flyer=False, title="Menu"))
    data = post(FlyerService(client=client), body()).get_json()

    assert data["is_event_flyer"] is False
    assert data["title"] == ""
    assert set(data["missing"]) == {"title", "date", "time", "location", "cost"}


def test_cleans_up_claudes_answer(post):
    client, _ = flyer_client(output=output(
        start_time="next thursday", end_time="2026-11-14T18:00:00-08:00", category="nightlife",
        title="  Fall   Climbing\nSocial ", missing=["Cost", "weather", "cost"],
    ))
    data = post(FlyerService(client=client), body()).get_json()

    assert data["start_time"] is None                    # not a real time
    assert data["end_time"] == "2026-11-14T18:00:00-08:00"
    assert data["category"] == ""                        # not one of the app's categories
    assert data["title"] == "Fall Climbing Social"
    assert data["missing"] == ["cost", "date", "time"]


def test_end_before_start_is_dropped(post):
    client, _ = flyer_client(output=output(end_time="2026-11-14T18:00:00-08:00"))
    assert post(FlyerService(client=client), body()).get_json()["end_time"] is None


@pytest.mark.parametrize("change, message", [
    ({"media_type": "image/gif"}, "media_type"),
    ({"image": "not base64!!"}, "base64"),
    ({"image": ""}, "required"),
    ({"image": base64.b64encode(b"GIF89a....").decode()}, "not a valid JPEG"),   # label says JPEG, bytes don't
    ({"now": "2026-11-12T10:00:00"}, "UTC offset"),
    ({"now": "soon"}, "ISO-8601"),
    ({"ocr_text": 5}, "ocr_text"),
])
def test_rejects_bad_requests(post, change, message):
    client, messages = flyer_client(output=output())
    response = post(FlyerService(client=client), body(**change))

    assert response.status_code == 400
    error = response.get_json()["error"]
    assert error["code"] == "invalid_flyer_request" and message in error["message"]
    assert messages.calls == []


def test_rejects_images_over_5_mb(post):
    client, messages = flyer_client(output=output())
    big = JPEG + b"\x00" * (5 * 1024 * 1024)
    response = post(FlyerService(client=client), body(raw=big))

    assert response.status_code == 400 and "5 MB" in response.get_json()["error"]["message"]
    assert messages.calls == []


def test_requires_sign_in(repository):
    client, _ = flyer_client(output=output())
    app = make_app(EventService(repository), flyer_service=FlyerService(client=client))
    assert app.test_client().post("/api/flyers/read", json=body()).status_code == 401


def test_claude_unavailable_is_503(post, monkeypatch, tmp_path):
    for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    response = post(FlyerService(), body())

    assert response.status_code == 503
    assert response.get_json()["error"]["code"] == "ai_unavailable"


def test_refusal_is_503(post):
    client, _ = flyer_client(output=None, stop_reason="refusal")
    assert post(FlyerService(client=client), body()).status_code == 503
