"""One place that calls Claude for the app's AI features (planner, flyer reader).

Each feature describes what it wants back as a Pydantic model; structured
outputs guarantee that shape. Any reason Claude can't answer (no key, key
rejected, busy, unreachable, declined) becomes AIUnavailableError with a
message that's safe to show to students, so the app can fall back on-device.
"""
import logging

import anthropic

MODEL = "claude-opus-5-5"
NOT_CONFIGURED = "The AI features aren't set up on this server yet (no ANTHROPIC_API_KEY)."

log = logging.getLogger(__name__)


class AIUnavailableError(Exception):
    """Claude can't answer right now. The message is shown to the user."""


def make_client():
    """Reads ANTHROPIC_API_KEY (or another configured credential) from the environment."""
    try:
        return anthropic.Anthropic(timeout=30.0, max_retries=1)
    except anthropic.AnthropicError as e:
        raise AIUnavailableError(NOT_CONFIGURED) from e


def parse(client, *, system, content, output_format, effort="low", max_tokens=4000, model=MODEL):
    """Asks Claude and returns its answer as an `output_format` instance."""
    try:
        response = client.beta.messages.parse(
            model=model,
            max_tokens=max_tokens,
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",                      # another model answers if this one declines
            output_config={"effort": effort},
            system=system,
            messages=[{"role": "user", "content": content}],
            output_format=output_format,
        )
    except anthropic.RateLimitError as e:
        raise AIUnavailableError("The AI is busy right now. Try again in a minute.") from e
    except (anthropic.AuthenticationError, anthropic.PermissionDeniedError) as e:
        raise AIUnavailableError("The server's Claude API key was rejected.") from e
    except anthropic.APIStatusError as e:
        log.warning("Claude request failed: %s (request id %s)", e.status_code, getattr(e, "request_id", None))
        raise AIUnavailableError("The AI couldn't answer right now.") from e
    except anthropic.APIConnectionError as e:
        raise AIUnavailableError("The server couldn't reach Claude.") from e
    except TypeError as e:
        # The SDK raises TypeError at request time when no credentials are configured.
        log.warning("No Claude credentials: %s", e)
        raise AIUnavailableError(NOT_CONFIGURED) from e

    if response.stop_reason == "refusal" or response.parsed_output is None:
        raise AIUnavailableError("The AI couldn't help with that request.")
    return response.parsed_output


def clip(text, limit):
    """Collapses whitespace and trims to `limit` characters."""
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"
