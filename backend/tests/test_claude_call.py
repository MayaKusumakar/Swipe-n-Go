"""services/claude_call.py turns every way Claude can fail into AIUnavailableError (a 503),
so the app falls back on-device instead of the server answering 500.

The planner, flyer reader and experimental text parser all call claude_call.parse, so
these cover all three. No test here reads real credentials: errors come from a fake client.
"""
from types import SimpleNamespace

import anthropic
import pytest
from pydantic import BaseModel

from services import claude_call
from services.claude_call import NOT_CONFIGURED, AIUnavailableError
from test_planner import body, fake_client, make_client  # noqa: F401 - make_client is a fixture
from services.planner_service import PlannerService


class _Answer(BaseModel):
    text: str


def _ask(error):
    client = SimpleNamespace(beta=SimpleNamespace(messages=SimpleNamespace(
        parse=lambda **kwargs: (_ for _ in ()).throw(error))))
    return claude_call.parse(client, system="s", content="c", output_format=_Answer)


@pytest.mark.parametrize("error", [
    # What the SDK raises at request time with no API key; which one depends on the machine.
    anthropic.CredentialsError("Credentials file not found at ~/.config/anthropic/credentials/default.json"),
    TypeError("Could not resolve authentication method"),
], ids=["credentials_error", "type_error"])
def test_missing_key_says_ai_is_not_set_up(error):
    with pytest.raises(AIUnavailableError) as raised:
        _ask(error)
    assert str(raised.value) == NOT_CONFIGURED


def test_any_other_sdk_error_is_still_unavailable():
    with pytest.raises(AIUnavailableError) as raised:
        _ask(anthropic.AnthropicError("something new in a later SDK"))
    assert str(raised.value) == "The AI couldn't answer right now."


def test_bugs_in_our_own_code_are_not_hidden():
    # Only SDK errors become 503s; a real bug should still surface as one.
    with pytest.raises(KeyError):
        _ask(KeyError("oops"))


def test_planner_route_answers_503_not_500_without_a_key(make_client):  # noqa: F811
    client, _ = fake_client(error=anthropic.CredentialsError("Credentials file not found"))
    response = make_client(PlannerService(client=client)).post("/api/planner", json=body())

    assert response.status_code == 503
    assert response.get_json()["error"] == {"code": "ai_unavailable", "message": NOT_CONFIGURED}
