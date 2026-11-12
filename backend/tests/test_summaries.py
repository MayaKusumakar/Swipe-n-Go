"""Event summaries: free template by default, Claude only when explicitly on, run by cron."""
from datetime import timedelta
from types import SimpleNamespace

import anthropic
import pytest

from conftest import FIXED_NOW, FakeEventRepository, make_app, make_event, signed_in
from services.event_service import EventService
from services.summary_service import (
    ClaudeSummaryWriter, SummaryService, TemplateSummaryWriter, default_writer,
)


def at(hours):
    return FIXED_NOW + timedelta(hours=hours)


def test_template_summary_uses_the_event_details():
    event = make_event(description="All skill levels welcome. Bring water.", attendee_count=2,
                       capacity=6, level="beginner", cost="Free", requires_approval=True)

    text = TemplateSummaryWriter().write(event)

    assert text == ("All skill levels welcome. 3 going, 3 spots left. Best for beginner level. "
                    "Cost: Free. The host approves each request.")


def test_template_summary_never_mentions_the_place():
    event = make_event(location_private=True, location_name="Secret Spot", address="1 Hidden Ln")
    text = TemplateSummaryWriter().write(event)
    assert "Secret" not in text and "Hidden" not in text


def test_full_and_solo_wording():
    assert "full" in TemplateSummaryWriter().write(make_event(attendee_count=1, capacity=2))
    assert "Just the host so far" in TemplateSummaryWriter().write(make_event(attendee_count=0))


def test_summarize_stale_writes_upcoming_and_clears_past():
    repo = FakeEventRepository()
    repo.events = [
        make_event("up", start_time=at(2), summary_stale=True),
        make_event("past", start_time=at(-2), summary_stale=True),
        make_event("fresh", start_time=at(2), summary="Old", summary_stale=False),
    ]

    written = SummaryService(repo, writer=TemplateSummaryWriter()).summarize_stale(FIXED_NOW)

    assert written == 1
    assert repo.get("up").summary and repo.get("up").summary_stale is False
    assert repo.get("past").summary is None and repo.get("past").summary_stale is False
    assert repo.get("fresh").summary == "Old"


def test_summary_stays_stale_if_attendance_changed_meanwhile():
    repo = FakeEventRepository()
    repo.events = [make_event("e", start_time=at(2), summary_stale=True)]

    class JoinWhileWriting:
        def write(self, event):
            repo.get("e").attendee_count += 1
            return "text"

    SummaryService(repo, writer=JoinWhileWriting()).summarize_stale(FIXED_NOW)
    assert repo.get("e").summary_stale is True


# Claude is opt-in, and every failure falls back to the free template.

def test_default_writer_is_free_unless_switched_on(monkeypatch):
    monkeypatch.delenv("AI_SUMMARIES", raising=False)
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
    assert isinstance(default_writer(), TemplateSummaryWriter)

    monkeypatch.setenv("AI_SUMMARIES", "on")
    monkeypatch.delenv("ANTHROPIC_API_KEY")
    assert isinstance(default_writer(), TemplateSummaryWriter)

    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
    assert isinstance(default_writer(), ClaudeSummaryWriter)


class FakeMessages:
    def __init__(self, response=None, error=None):
        self.response, self.error, self.calls = response, error, []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if self.error:
            raise self.error
        return self.response


def claude_writer(messages):
    return ClaudeSummaryWriter(client=SimpleNamespace(beta=SimpleNamespace(messages=messages)))


def text_response(text, stop_reason="end_turn"):
    return SimpleNamespace(stop_reason=stop_reason, content=[
        SimpleNamespace(type="thinking", thinking=""), SimpleNamespace(type="text", text=text),
    ])


def test_claude_writer_returns_its_text_and_never_sends_the_place():
    messages = FakeMessages(text_response("  Easy social run.  "))
    event = make_event(location_name="Secret Spot", address="1 Hidden Ln")

    assert claude_writer(messages).write(event) == "Easy social run."
    sent = messages.calls[0]["messages"][0]["content"]
    assert "Secret" not in sent and "Hidden" not in sent


@pytest.mark.parametrize("messages", [
    FakeMessages(error=anthropic.APIConnectionError(request=SimpleNamespace(
        method="POST", url="https://api.anthropic.com/v1/messages", headers={}))),
    FakeMessages(text_response("", stop_reason="refusal")),
    FakeMessages(text_response("   ")),
])
def test_claude_failures_fall_back_to_the_template(messages):
    event = make_event(attendee_count=0)
    assert claude_writer(messages).write(event) == TemplateSummaryWriter().write(event)


# The cron route.

def app_client(repo):
    service = EventService(repo, clock=lambda: FIXED_NOW)
    summaries = SummaryService(repo, writer=TemplateSummaryWriter())
    return signed_in(make_app(service, summary_service=summaries))


def test_task_route_runs_locally_from_this_machine(monkeypatch):
    monkeypatch.delenv("GAE_ENV", raising=False)
    repo = FakeEventRepository()
    repo.events = [make_event("e", start_time=FIXED_NOW + timedelta(days=3650), summary_stale=True)]

    response = app_client(repo).get("/tasks/summarize-stale")

    assert response.status_code == 200
    assert response.get_json() == {"summarized": 1}
    assert repo.get("e").summary


def test_task_route_refuses_other_machines_locally(monkeypatch):
    monkeypatch.delenv("GAE_ENV", raising=False)
    response = app_client(FakeEventRepository()).get(
        "/tasks/summarize-stale", environ_base={"REMOTE_ADDR": "192.168.1.20"})
    assert response.status_code == 403


def test_on_app_engine_only_cron_or_cloud_tasks_may_call(monkeypatch):
    monkeypatch.setenv("GAE_ENV", "standard")
    client = app_client(FakeEventRepository())

    assert client.get("/tasks/summarize-stale").status_code == 403
    assert client.get("/tasks/summarize-stale", headers={"X-Appengine-Cron": "true"}).status_code == 200
    assert client.post("/tasks/summarize-stale", headers={"X-AppEngine-QueueName": "summaries"}).status_code == 200


def test_public_event_json_includes_the_summary(client, repository):
    repository.events = [make_event("e", summary="Easy pace, coffee after.")]
    assert client.get("/api/events").get_json()["events"][0]["summary"] == "Easy pace, coffee after."
