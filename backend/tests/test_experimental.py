"""Experiments (experimental/): off by default, and correct when switched on."""
from types import SimpleNamespace

import pytest

from conftest import FIXED_NOW, make_app, signed_in
from experimental import enabled_experiments
from experimental.event_parse import EventTextParser, _EventTextOutput
from experimental.rate_limit import RateLimiter
from main import create_app
from services.auth_service import AuthService
from services.event_service import EventService
from repositories.user_repository import InMemoryUserRepository

NOW = "2026-11-12T10:00:00-08:00"


# MARK: Off by default

def _rules(app):
    return sorted((r.rule, tuple(sorted(r.methods))) for r in app.url_map.iter_rules())


def test_default_app_has_no_experimental_routes(repository, monkeypatch):
    monkeypatch.delenv("EXPERIMENTS", raising=False)
    app = create_app(EventService(repository), auth_service=AuthService(client_ids=[], dev_mode=True),
                     user_repository=InMemoryUserRepository())
    assert app.extensions["experiments"] == ()
    assert not [rule for rule, _ in _rules(app) if "experimental" in rule]
    assert "event_text_parser" not in app.extensions
    assert "experimental_rate_limiter" not in app.extensions


def test_switching_experiments_on_only_adds_routes(repository):
    off = make_app(EventService(repository), experiments="")
    on = make_app(EventService(repository), experiments="event_parse,status")
    added = set(_rules(on)) - set(_rules(off))
    assert set(_rules(off)) <= set(_rules(on))
    assert {rule for rule, _ in added} == {"/api/experimental/events/parse", "/api/experimental/status"}


def test_routes_are_404_when_off(repository):
    client = signed_in(make_app(EventService(repository), experiments=""))
    assert client.post("/api/experimental/events/parse", json={"text": "x", "now": NOW}).status_code == 404
    assert client.get("/api/experimental/status").status_code == 404


def test_one_experiment_does_not_switch_on_the_other(repository):
    client = signed_in(make_app(EventService(repository), experiments="status"))
    assert client.get("/api/experimental/status").status_code == 200
    assert client.post("/api/experimental/events/parse", json={"text": "x", "now": NOW}).status_code == 404


@pytest.mark.parametrize("raw, expected", [
    ("", ()),
    ("event_parse", ("event_parse",)),
    (" Status , event_parse ", ("event_parse", "status")),
    ("nope,status", ("status",)),
])
def test_enabled_experiments(raw, expected):
    assert enabled_experiments(raw) == expected


def test_reads_the_environment(monkeypatch):
    monkeypatch.setenv("EXPERIMENTS", "status")
    assert enabled_experiments() == ("status",)


def test_experimental_routes_need_sign_in(repository):
    app = make_app(EventService(repository), experiments="event_parse,status")
    assert app.test_client().get("/api/experimental/status").status_code == 401
    assert app.test_client().post("/api/experimental/events/parse", json={}).status_code == 401


# MARK: event_parse

class FakeMessages:
    def __init__(self, output=None, stop_reason="end_turn"):
        self.output, self.stop_reason, self.calls = output, stop_reason, []

    def parse(self, **kwargs):
        self.calls.append(kwargs)
        return SimpleNamespace(parsed_output=self.output, stop_reason=self.stop_reason)


def output(**overrides):
    fields = dict(
        is_event=True, title="Pickup Soccer", start_time="2026-11-14T15:00:00-08:00",
        end_time="2026-11-14T17:00:00-08:00", location_name="ARC Fields", address="",
        description="Casual pickup soccer, all levels.", cost="Free", category="sports", missing=[],
    )
    fields.update(overrides)
    return _EventTextOutput(**fields)


@pytest.fixture
def parse_app(repository):
    def build(out=None, stop_reason="end_turn", parser=None):
        app = make_app(EventService(repository, clock=lambda: FIXED_NOW), experiments="event_parse")
        messages = FakeMessages(out if out is not None else output(), stop_reason)
        client = SimpleNamespace(beta=SimpleNamespace(messages=messages))
        app.extensions["event_text_parser"] = parser or EventTextParser(client=client)
        return signed_in(app), messages
    return build


def test_parses_text(parse_app):
    client, messages = parse_app()
    response = client.post("/api/experimental/events/parse",
                           json={"text": "pickup soccer sat 3-5pm at the ARC fields, free", "now": NOW})

    assert response.status_code == 200
    data = response.get_json()
    assert data["is_event"] is True
    assert data["title"] == "Pickup Soccer"
    assert data["start_time"] == "2026-11-14T15:00:00-08:00"
    assert data["category"] == "sports"
    assert data["model"] == "claude-opus-5-5"

    call = messages.calls[0]
    assert call["output_format"] is _EventTextOutput
    text = call["messages"][0]["content"][0]["text"]
    assert "2026-11-12T10:00:00-08:00 (Thursday)" in text
    assert "<description>\npickup soccer sat 3-5pm" in text


def test_cleans_answer_like_the_flyer_reader(parse_app):
    client, _ = parse_app(output(start_time="saturday", end_time="2026-11-14T14:00:00-08:00",
                                 category="nightlife", missing=["Cost", "weather"]))
    data = client.post("/api/experimental/events/parse", json={"text": "soccer", "now": NOW}).get_json()
    assert data["start_time"] is None
    assert data["category"] == ""
    assert data["missing"] == ["cost", "date", "time"]


def test_not_an_event(parse_app):
    client, _ = parse_app(output(is_event=False, title="hi"))
    data = client.post("/api/experimental/events/parse", json={"text": "hello there", "now": NOW}).get_json()
    assert data["is_event"] is False and data["title"] == ""
    assert set(data["missing"]) == {"title", "date", "time", "location", "cost"}


@pytest.mark.parametrize("payload, message", [
    ({"now": NOW}, "text is required"),
    ({"text": "   ", "now": NOW}, "text is required"),
    ({"text": 5, "now": NOW}, "text is required"),
    ({"text": "x" * 1001, "now": NOW}, "at most 1000"),
    ({"text": "soccer"}, "ISO-8601"),
    ({"text": "soccer", "now": "2026-11-12T10:00:00"}, "UTC offset"),
])
def test_rejects_bad_requests(parse_app, payload, message):
    client, messages = parse_app()
    response = client.post("/api/experimental/events/parse", json=payload)
    assert response.status_code == 400
    error = response.get_json()["error"]
    assert error["code"] == "invalid_parse_request" and message in error["message"]
    assert messages.calls == []


def test_refusal_is_503(parse_app):
    client, _ = parse_app(stop_reason="refusal")
    response = client.post("/api/experimental/events/parse", json={"text": "soccer", "now": NOW})
    assert response.status_code == 503 and response.get_json()["error"]["code"] == "ai_unavailable"


def test_no_api_key_is_503(parse_app, monkeypatch, tmp_path):
    for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    client, _ = parse_app(parser=EventTextParser())
    response = client.post("/api/experimental/events/parse", json={"text": "soccer", "now": NOW})
    assert response.status_code == 503


def test_parse_is_rate_limited_per_user(parse_app):
    client, messages = parse_app()
    for _ in range(10):
        assert client.post("/api/experimental/events/parse", json={"text": "soccer", "now": NOW}).status_code == 200
    response = client.post("/api/experimental/events/parse", json={"text": "soccer", "now": NOW})
    assert response.status_code == 429 and response.get_json()["error"]["code"] == "rate_limited"
    assert len(messages.calls) == 10


# MARK: status

def test_status_ok(repository, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    client = signed_in(make_app(EventService(repository, clock=lambda: FIXED_NOW), experiments="status"))
    data = client.get("/api/experimental/status").get_json()
    assert data["status"] == "ok"
    assert data["datastore"] == {"ok": True}
    assert data["ai"]["configured"] is False and data["ai"]["summaries"] == "template"
    assert data["experiments"] == ["status"]
    assert data["environment"] == "local"


def test_status_degraded_when_store_is_down(repository):
    repository.error = OSError("no project")
    client = signed_in(make_app(EventService(repository, clock=lambda: FIXED_NOW), experiments="status"))
    data = client.get("/api/experimental/status").get_json()
    assert data["status"] == "degraded"
    assert data["datastore"] == {"ok": False, "error": "OSError"}


# MARK: rate limiter

def test_rate_limiter_window_resets():
    now = [0.0]
    limiter = RateLimiter(clock=lambda: now[0])
    assert limiter.allow("k", 2) and limiter.allow("k", 2)
    assert not limiter.allow("k", 2)
    assert limiter.allow("other", 2)
    now[0] = 60.0
    assert limiter.allow("k", 2)
    assert limiter.allow("k", 0)
