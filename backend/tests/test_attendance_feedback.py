"""PUT /api/events/<id>/attendees/me/attendance: "Did you attend?" after an event, with feedback."""
from datetime import timedelta
from unittest.mock import MagicMock

import pytest

from conftest import FIXED_NOW, make_app, signed_in
from models import APPROVED, PENDING, Attendee
from repositories.event_repository import EventRepository
from services.event_service import EventService
from test_attendees_api import guest, host, join
from test_create_event_api import VALID_BODY


@pytest.fixture
def clock():
    return {"now": FIXED_NOW}


@pytest.fixture
def app_client(repository, clock):
    return signed_in(make_app(EventService(repository, clock=lambda: clock["now"])))


@pytest.fixture
def ended_event(app_client, clock):
    """An approved guest (Maya) of an event that has since ended."""
    event = app_client.post("/api/events", json=VALID_BODY | {"requires_approval": True}).get_json()
    join(app_client, event["id"])
    assert app_client.post(f"/api/events/{event['id']}/attendees/dev-maya@ucdavis.edu/approve").status_code == 200
    clock["now"] = FIXED_NOW + timedelta(days=2)
    return event


def answer(client, event_id, body, name="Maya"):
    return client.put(f"/api/events/{event_id}/attendees/me/attendance", json=body, headers=guest(name))


def test_guest_who_went_leaves_feedback_for_the_host(app_client, ended_event, repository):
    response = answer(app_client, ended_event["id"], {"attended": True, "feedback": "  Great night, more of these!  "})

    assert response.status_code == 200
    data = response.get_json()
    assert (data["attended"], data["feedback"]) == (True, "Great night, more of these!")
    stored = repository.attendees[(ended_event["id"], "dev-maya@ucdavis.edu")]
    assert stored.feedback_at == FIXED_NOW + timedelta(days=2)

    # The host sees it in the attendee list.
    attendees = app_client.get(f"/api/events/{ended_event['id']}/attendees", headers=host()).get_json()["attendees"]
    assert attendees[0]["attended"] is True
    assert attendees[0]["feedback"] == "Great night, more of these!"


def test_feedback_is_optional_and_dropped_when_they_didnt_go(app_client, ended_event):
    assert answer(app_client, ended_event["id"], {"attended": True}).get_json()["feedback"] is None
    data = answer(app_client, ended_event["id"], {"attended": False, "feedback": "n/a"}).get_json()
    assert data["attended"] is False and data["feedback"] is None


def test_unanswered_attendees_have_no_answer_fields(app_client, ended_event):
    attendees = app_client.get(f"/api/events/{ended_event['id']}/attendees", headers=host()).get_json()["attendees"]
    assert "attended" not in attendees[0]


def test_not_before_the_event_is_over(app_client, ended_event, clock):
    clock["now"] = FIXED_NOW
    assert answer(app_client, ended_event["id"], {"attended": True}).status_code == 403


def test_only_approved_guests_can_answer(app_client, ended_event, repository):
    assert answer(app_client, ended_event["id"], {"attended": True}, name="Stranger").status_code == 403
    key = (ended_event["id"], "dev-maya@ucdavis.edu")
    repository.attendees[key] = Attendee(id=key[1], event_id=key[0], name="Maya", status=PENDING, created_at=FIXED_NOW)
    assert answer(app_client, ended_event["id"], {"attended": True}).status_code == 403


@pytest.mark.parametrize("body", [{}, {"attended": "yes"}, {"attended": True, "feedback": 5},
                                  {"attended": True, "feedback": "x" * 1001}])
def test_bad_bodies_are_400(app_client, ended_event, body):
    response = answer(app_client, ended_event["id"], body)
    assert response.status_code == 400
    assert response.get_json()["error"]["code"] == "invalid_attendance"


def test_unknown_event_is_404(app_client):
    assert answer(app_client, "nope", {"attended": True}).status_code == 404


def test_datastore_keeps_feedback_unindexed():
    client = MagicMock()
    client.key.side_effect = lambda *path: MagicMock(id_or_name=path[-1], parent=MagicMock(id_or_name=path[1]))
    entity = MagicMock()
    entity.exclude_from_indexes = set()
    stored = {"name": "Maya", "status": APPROVED, "created_at": FIXED_NOW}
    entity.get.side_effect = lambda k, d=None: stored.get(k, d)
    entity.__getitem__.side_effect = stored.__getitem__
    entity.update.side_effect = stored.update
    entity.key = client.key("Event", "e1", "Attendee", "maya")
    client.get.return_value = entity

    attendee = EventRepository(client=client).set_attendance("e1", "maya", True, "Fun", FIXED_NOW)

    assert "feedback" in entity.exclude_from_indexes
    client.put.assert_called_once_with(entity)
    assert attendee.attended is True and attendee.feedback == "Fun"
