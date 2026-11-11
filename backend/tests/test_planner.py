from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import anthropic
import pytest

from main import create_app
from services.planner_service import PlannerService, PlannerUnavailableError, _PickOutput, _PlanOutput

PACIFIC = timezone(timedelta(hours=-8))
NOW = datetime(2026, 11, 11, 12, 0, tzinfo=PACIFIC)


def event(event_id, **overrides):
    body = {
        "id": event_id,
        "title": "Pickup basketball 3v3",
        "category": "sports",
        "start_time": (NOW + timedelta(days=1, hours=6)).isoformat(),
        "duration_minutes": 90,
        "location_name": "ARC Courts",
        "distance_miles": 1.1,
        "cost": "Free",
        "level": "intermediate",
        "attendee_count": 3,
        "spots_left": 3,
        "requires_approval": False,
        "tags": ["Casual"],
    }
    body.update(overrides)
    return body


def body(**overrides):
    payload = {
        "query": "free tomorrow after 5, want something active, I don't know anyone",
        "now": NOW.isoformat(),
        "interests": ["run", "food"],
        "events": [event("a"), event("b", title="Leg day spotter needed", category="gym")],
    }
    payload.update(overrides)
    return payload


class FakeMessages:
    def __init__(self, output=None, stop_reason="end_turn", error=None):
        self.output, self.stop_reason, self.error = output, stop_reason, error
        self.calls = []

    def parse(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return SimpleNamespace(parsed_output=self.output, stop_reason=self.stop_reason)


def fake_client(**kwargs):
    messages = FakeMessages(**kwargs)
    return SimpleNamespace(beta=SimpleNamespace(messages=messages)), messages


def output(picks, **overrides):
    fields = dict(
        understood="Tomorrow after 5 · something active · meet people",
        window_start="2026-11-12T17:00:00-08:00",
        window_end="2026-11-13T00:00:00-08:00",
        picks=[_PickOutput(event_id=i, reason=r) for i, r in picks],
        note="",
    )
    fields.update(overrides)
    return _PlanOutput(**fields)


@pytest.fixture
def make_client():
    def build(planner):
        app = create_app(event_service=SimpleNamespace(), planner_service=planner)
        return app.test_client()
    return build


def test_returns_picks_from_claude(make_client):
    client, messages = fake_client(output=output([("a", "3 people already going, 6 PM at the ARC.")]))
    response = make_client(PlannerService(client=client)).post("/api/planner", json=body())

    assert response.status_code == 200
    data = response.get_json()
    assert data["understood"].startswith("Tomorrow after 5")
    assert data["picks"] == [{"event_id": "a", "reason": "3 people already going, 6 PM at the ARC."}]
    assert data["window_start"] == "2026-11-12T17:00:00-08:00"
    assert data["model"] == "claude-opus-5-5"


def test_sends_context_and_uses_structured_output(make_client):
    client, messages = fake_client(output=output([]))
    make_client(PlannerService(client=client)).post("/api/planner", json=body())

    call = messages.calls[0]
    assert call["model"] == "claude-opus-5-5"
    assert call["output_format"] is _PlanOutput
    assert call["fallbacks"] == "default"
    assert call["output_config"] == {"effort": "low"}
    content = call["messages"][0]["content"]
    assert "I don't know anyone" in content
    assert '"event_id": "a"' in content and '"weekday": "Wednesday"' in content


def test_event_times_are_sent_in_the_students_time_zone(make_client):
    client, messages = fake_client(output=output([]))
    utc_start = (NOW + timedelta(days=1, hours=6)).astimezone(timezone.utc).isoformat()   # 2026-11-13T02:00:00+00:00
    make_client(PlannerService(client=client)).post("/api/planner", json=body(events=[event("a", start_time=utc_start)]))

    content = messages.calls[0]["messages"][0]["content"]
    assert '"starts": "2026-11-12T18:00:00-08:00"' in content


def test_drops_unknown_duplicate_and_extra_picks(make_client):
    picks = [("a", "ok"), ("ghost", "invented"), ("a", "duplicate"), ("b", "x" * 400)]
    client, _ = fake_client(output=output(picks))
    data = make_client(PlannerService(client=client)).post("/api/planner", json=body()).get_json()

    assert [p["event_id"] for p in data["picks"]] == ["a", "b"]
    assert len(data["picks"][1]["reason"]) <= 160


def test_bad_window_becomes_null(make_client):
    client, _ = fake_client(output=output([("a", "ok")], window_start="tomorrow", window_end="2026-11-12T23:00:00"))
    data = make_client(PlannerService(client=client)).post("/api/planner", json=body()).get_json()

    assert data["window_start"] is None and data["window_end"] is None


def test_no_events_skips_claude(make_client):
    client, messages = fake_client(output=output([]))
    data = make_client(PlannerService(client=client)).post("/api/planner", json=body(events=[])).get_json()

    assert data["picks"] == [] and "no upcoming events" in data["note"]
    assert messages.calls == []


def test_refusal_is_503(make_client):
    client, _ = fake_client(output=None, stop_reason="refusal")
    response = make_client(PlannerService(client=client)).post("/api/planner", json=body())

    assert response.status_code == 503
    assert response.get_json()["error"]["code"] == "ai_unavailable"


def test_api_errors_are_503(make_client):
    request = SimpleNamespace(method="POST", url="https://api.anthropic.com/v1/messages", headers={})
    error = anthropic.APIConnectionError(request=request)
    client, _ = fake_client(error=error)
    response = make_client(PlannerService(client=client)).post("/api/planner", json=body())

    assert response.status_code == 503
    assert "reach Claude" in response.get_json()["error"]["message"]


def test_missing_api_key_is_503(make_client, monkeypatch, tmp_path):
    # Real SDK, no credentials anywhere: must be a friendly 503, not a 500.
    for name in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE"):
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("HOME", str(tmp_path))
    response = make_client(PlannerService()).post("/api/planner", json=body())

    assert response.status_code == 503
    assert "ANTHROPIC_API_KEY" in response.get_json()["error"]["message"]


@pytest.mark.parametrize("change", [
    {"query": ""},
    {"query": 5},
    {"now": "2026-11-11T12:00:00"},                 # no UTC offset
    {"now": "noon"},
    {"interests": "running"},
    {"events": "lots"},
    {"events": [event("a"), event("a")]},           # duplicate ids
    {"events": [event("a", duration_minutes=0)]},
    {"events": [event("a", distance_miles=-1)]},
    {"events": [event("a", requires_approval="no")]},
    {"events": [event(str(i)) for i in range(81)]},
])
def test_rejects_bad_requests(make_client, change):
    client, messages = fake_client(output=output([]))
    response = make_client(PlannerService(client=client)).post("/api/planner", json=body(**change))

    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_planner_request"
    assert messages.calls == []


def test_unavailable_error_type():
    assert issubclass(PlannerUnavailableError, Exception)
