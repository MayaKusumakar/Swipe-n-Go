"""A plan's group chat: GET/POST /api/events/<id>/messages, for the host and approved guests."""
import re
from datetime import timedelta
from unittest.mock import MagicMock

import pytest
from google.api_core.exceptions import ServiceUnavailable
from google.cloud.datastore import Key

from conftest import FIXED_NOW, HOST_NAME, make_app, make_event, signed_in, user_id
from models import Message
from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository
from services.event_service import EventService
from test_attendees_api import create, guest, join


@pytest.fixture
def client(repository):
    """Signed in as the host; the clock moves 1 s per call so messages get increasing ids."""
    ticks = iter(range(10_000))
    service = EventService(repository, clock=lambda: FIXED_NOW + timedelta(seconds=next(ticks)))
    return signed_in(make_app(service))


def send(client, event_id, text, name=None, **extra):
    headers = guest(name) if name else None
    return client.post(f"/api/events/{event_id}/messages", json={"text": text} | extra, headers=headers)


def read(client, event_id, name=None, **params):
    headers = guest(name) if name else None
    return client.get(f"/api/events/{event_id}/messages", query_string=params, headers=headers)


def texts(client, event_id, name=None, kind="text"):
    """The chat's lines of one kind, oldest first."""
    return [m["text"] for m in read(client, event_id, name=name).get_json()["messages"] if m["kind"] == kind]


@pytest.fixture
def plan(client):
    """An open plan with Maya and Sam joined."""
    event = create(client)
    join(client, event["id"], name="Maya")
    join(client, event["id"], name="Sam")
    return event


def test_host_and_guests_see_each_others_messages(client, plan):
    assert send(client, plan["id"], "See you at 7!").status_code == 201
    assert send(client, plan["id"], "  I'll bring snacks  ", name="Maya").status_code == 201
    assert send(client, plan["id"], "Running late", name="Sam").status_code == 201

    for name in (None, "Maya", "Sam"):
        body = read(client, plan["id"], name=name).get_json()
        assert [(m["sender_name"], m["text"]) for m in body["messages"] if m["kind"] == "text"] == [
            (HOST_NAME, "See you at 7!"), ("Maya", "I'll bring snacks"), ("Sam", "Running late"),
        ]
        assert body["has_more"] is False


def test_a_message_has_its_sender_and_time(client, plan):
    message = send(client, plan["id"], "Hi", name="Maya", client_id="A1B2-c3").get_json()
    assert message["sender_id"] == user_id("Maya")
    assert message["client_id"] == "A1B2-c3"
    assert message["kind"] == "text"
    assert re.fullmatch(r"2026-11-05T12:00:\d\d\.000\+00:00", message["created_at"])  # always milliseconds
    assert len(message["id"]) == 22


def test_after_returns_only_newer_messages(client, plan):
    first = send(client, plan["id"], "one").get_json()
    send(client, plan["id"], "two", name="Maya")
    send(client, plan["id"], "three", name="Sam")

    body = read(client, plan["id"], name="Maya", after=first["id"]).get_json()
    assert [m["text"] for m in body["messages"]] == ["two", "three"]
    last = body["messages"][-1]["id"]
    assert read(client, plan["id"], after=last).get_json()["messages"] == []


def test_limit_pages_through_the_chat(client):
    plan = create(client)
    for i in range(5):
        send(client, plan["id"], f"m{i}")
    page = read(client, plan["id"], limit=2).get_json()
    assert [m["text"] for m in page["messages"]] == ["m0", "m1"] and page["has_more"] is True
    page = read(client, plan["id"], limit=3, after=page["messages"][-1]["id"]).get_json()
    assert [m["text"] for m in page["messages"]] == ["m2", "m3", "m4"] and page["has_more"] is False


def test_resending_with_the_same_client_id_stores_one_message(client, plan):
    first = send(client, plan["id"], "Hi", name="Maya", client_id="abc-123")
    again = send(client, plan["id"], "Hi", name="Maya", client_id="abc-123")
    assert first.status_code == 201 and again.status_code == 200
    assert again.get_json()["id"] == first.get_json()["id"]
    assert texts(client, plan["id"]) == ["Hi"]


# Join and leave lines come from the server, so every phone shows the same ones.

def test_joining_adds_a_line_from_the_server(client, plan):
    body = read(client, plan["id"]).get_json()["messages"]
    joins = [m for m in body if m["kind"] == "system"]
    assert [m["text"] for m in joins] == ["Maya joined the plan", "Sam joined the plan"]
    assert joins[0]["sender_id"] == user_id("Maya") and joins[0]["client_id"] is None


def test_lines_use_the_first_name(client):
    event = create(client)
    client.patch("/api/auth/me", json={"name": "Maya Kusumakar"}, headers=guest("Maya"))
    join(client, event["id"], name="Maya")
    assert texts(client, event["id"], kind="system") == ["Maya joined the plan"]


def test_approval_adds_the_line_not_the_request(client):
    event = create(client, requires_approval=True)
    join(client, event["id"], name="Maya")
    assert texts(client, event["id"], kind="system") == []
    client.post(f"/api/events/{event['id']}/attendees/{user_id('Maya')}/approve")
    client.post(f"/api/events/{event['id']}/attendees/{user_id('Maya')}/approve")   # again: no second line
    assert texts(client, event["id"], kind="system") == ["Maya joined the plan"]


def test_leaving_and_being_removed_add_lines(client, plan):
    client.delete(f"/api/events/{plan['id']}/attendees/{user_id('Maya')}", headers=guest("Maya"))
    client.delete(f"/api/events/{plan['id']}/attendees/{user_id('Sam')}")
    assert texts(client, plan["id"], kind="system")[2:] == ["Maya left the plan", "Sam was removed from the plan"]


def test_withdrawn_or_declined_requests_add_nothing(client):
    event = create(client, requires_approval=True)
    join(client, event["id"], name="Maya")
    join(client, event["id"], name="Sam")
    client.delete(f"/api/events/{event['id']}/attendees/{user_id('Maya')}", headers=guest("Maya"))
    client.delete(f"/api/events/{event['id']}/attendees/{user_id('Sam')}")
    assert texts(client, event["id"], kind="system") == []


def test_a_failed_line_does_not_undo_the_join(client, repository):
    event = create(client)

    def down(message):
        raise ServiceUnavailable("down")
    repository.add_message = down
    assert client.post(f"/api/events/{event['id']}/attendees", headers=guest("Maya")).status_code == 201


def test_messages_cannot_be_sent_as_system_lines(client, plan):
    message = send(client, plan["id"], "Maya left the plan", name="Sam", kind="system").get_json()
    assert message["kind"] == "text"


def test_strangers_cannot_read_or_send(client, plan):
    assert send(client, plan["id"], "hello?", name="Stranger").status_code == 403
    assert read(client, plan["id"], name="Stranger").status_code == 403


def test_pending_requests_join_the_chat_once_approved(client):
    event = create(client, requires_approval=True)
    join(client, event["id"], name="Maya")
    assert read(client, event["id"], name="Maya").status_code == 403

    client.post(f"/api/events/{event['id']}/attendees/{user_id('Maya')}/approve")
    assert send(client, event["id"], "Thanks!", name="Maya").status_code == 201


def test_removed_guests_lose_the_chat(client, plan):
    client.delete(f"/api/events/{plan['id']}/attendees/{user_id('Sam')}")
    assert read(client, plan["id"], name="Sam").status_code == 403


def test_sender_name_is_the_chosen_profile_name(client, plan):
    client.patch("/api/auth/me", json={"name": "Maya K."}, headers=guest("Maya"))
    assert send(client, plan["id"], "hi", name="Maya").get_json()["sender_name"] == "Maya K."


@pytest.mark.parametrize("body", [{}, {"text": ""}, {"text": "   "}, {"text": 5}, {"text": "x" * 2001},
                                  {"text": "hi", "client_id": "has space"}, {"text": "hi", "client_id": 7}])
def test_bad_messages_are_400(client, plan, body):
    response = client.post(f"/api/events/{plan['id']}/messages", json=body)
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_message"


@pytest.mark.parametrize("params", [{"after": "nope"}, {"limit": "0"}, {"limit": "101"}, {"limit": "x"}])
def test_bad_read_parameters_are_400(client, plan, params):
    assert read(client, plan["id"], **params).status_code == 400


def test_unknown_event_is_404(client):
    assert send(client, "nope", "hi").status_code == 404
    assert read(client, "nope").status_code == 404


def test_store_down_is_503(client, plan, repository):
    repository.error = ServiceUnavailable("down")
    assert send(client, plan["id"], "hi").status_code == 503


def test_deleting_the_plan_deletes_its_chat(client, plan, repository):
    send(client, plan["id"], "hi")
    client.delete(f"/api/events/{plan['id']}")
    assert repository.messages == {}


def test_messages_are_rate_limited(client, plan):
    codes = [send(client, plan["id"], f"m{i}").status_code for i in range(31)]
    assert codes[:30] == [201] * 30 and codes[30] == 429


def test_memory_store_keeps_chats_per_event():
    store = InMemoryEventRepository([make_event("a"), make_event("b")])
    message = Message("0000000000001-00000000", "a", "u", "U", "hi", FIXED_NOW, client_id="c1")
    assert store.add_message(message) == (message, True)
    assert store.add_message(message) == (message, False)
    assert store.list_messages("a", None, 10) == [message]
    assert store.list_messages("b", None, 10) == []
    assert store.add_message(Message("1-0", "gone", "u", "U", "hi", FIXED_NOW)) is None
    store.delete_event("a", FIXED_NOW)
    assert store.list_messages("a", None, 10) == []


def test_datastore_reads_messages_after_a_key_in_key_order():
    client = MagicMock()
    client.key.side_effect = lambda *path: Key(*path, project="test")
    EventRepository(client=client).list_messages("e1", "0000000000001-00000000", 10)

    query = client.query.return_value
    client.query.assert_called_with(kind="Message", ancestor=Key("Event", "e1", project="test"))
    key_filter = query.add_filter.call_args.kwargs["filter"]
    assert (key_filter.property_name, key_filter.operator) == ("__key__", ">")
    assert key_filter.value.flat_path == ("Event", "e1", "Message", "0000000000001-00000000")
    assert query.order == ["__key__"]
    query.fetch.assert_called_with(limit=10)


def test_datastore_send_returns_the_earlier_copy_of_a_retry():
    client = MagicMock()
    earlier = MagicMock()
    earlier.key.id_or_name = "0000000000001-00000000"
    earlier.key.parent.id_or_name = "e1"
    stored = {"sender_id": "u", "sender_name": "U", "text": "hi", "created_at": FIXED_NOW, "client_id": "c1"}
    earlier.get.side_effect = lambda k, d=None: stored.get(k, d)
    earlier.__getitem__.side_effect = stored.__getitem__
    client.query.return_value.fetch.return_value = [earlier]

    message = Message("0000000000002-00000000", "e1", "u", "U", "hi", FIXED_NOW, client_id="c1")
    found, created = EventRepository(client=client).add_message(message)

    assert created is False and found.id == "0000000000001-00000000"
    client.put.assert_not_called()

    client.query.return_value.fetch.return_value = []
    assert EventRepository(client=client).add_message(message) == (message, True)
    assert client.put.call_args.args[0]["text"] == "hi"
