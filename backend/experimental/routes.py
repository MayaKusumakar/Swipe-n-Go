"""Routes for the experiments in experimental/__init__.py.

Registered only when at least one experiment is on, and each route answers
404 unless its own experiment is on. They live under /api/, so the sign-in
check in api/auth.py applies to them like every other /api route.
"""
import os
from datetime import datetime, timezone

from flask import Blueprint, abort, current_app, g, jsonify, request

from api.errors import error_response
from experimental.event_parse import MAX_TEXT
from services.claude_call import MODEL, AIUnavailableError
from services.event_service import ServiceUnavailableError

experimental_bp = Blueprint("experimental", __name__, url_prefix="/api/experimental")

PARSE_LIMIT_PER_MINUTE = 10
STATUS_LIMIT_PER_MINUTE = 30


def _require(name):
    if name not in current_app.extensions.get("experiments", ()):
        abort(404)


def _rate_limited(bucket, limit):
    limiter = current_app.extensions["experimental_rate_limiter"]
    if limiter.allow(f"{bucket}:{g.user.id}", limit):
        return None
    return error_response(429, "rate_limited", "Too many requests. Try again in a minute.")


class _BadRequest(ValueError):
    pass


def _parse_body(body):
    if not isinstance(body, dict):
        raise _BadRequest("request body must be a JSON object")
    text = body.get("text")
    if not isinstance(text, str) or not text.strip():
        raise _BadRequest("text is required")
    text = text.strip()
    if len(text) > MAX_TEXT:
        raise _BadRequest(f"text must be at most {MAX_TEXT} characters")
    try:
        now = datetime.fromisoformat(str(body.get("now")).replace("Z", "+00:00"))
    except ValueError:
        raise _BadRequest("now must be an ISO-8601 date-time") from None
    if now.tzinfo is None:
        raise _BadRequest("now must include a UTC offset")
    return text, now


@experimental_bp.post("/events/parse")
def parse_event_text():
    _require("event_parse")
    try:
        text, now = _parse_body(request.get_json(silent=True))
    except _BadRequest as e:
        return error_response(400, "invalid_parse_request", str(e))
    limited = _rate_limited("event_parse", PARSE_LIMIT_PER_MINUTE)
    if limited:
        return limited
    try:
        draft = current_app.extensions["event_text_parser"].parse(text, now)
    except AIUnavailableError as e:
        current_app.logger.warning("Event text parser unavailable: %s", e)
        return error_response(503, "ai_unavailable", str(e))
    return jsonify(draft.to_dict())


@experimental_bp.get("/status")
def status():
    """Health for the team. Free: checks Datastore with one small read and never calls Claude."""
    _require("status")
    limited = _rate_limited("status", STATUS_LIMIT_PER_MINUTE)
    if limited:
        return limited

    datastore = {"ok": True}
    try:
        current_app.extensions["event_service"].list_upcoming_events(1)
    except ServiceUnavailableError as e:
        cause = e.__cause__ or e
        datastore = {"ok": False, "error": type(cause).__name__}

    ai_configured = bool(os.environ.get("ANTHROPIC_API_KEY"))
    return jsonify({
        "status": "ok" if datastore["ok"] else "degraded",
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "environment": "app_engine" if os.environ.get("GAE_ENV") else "local",
        "datastore": datastore,
        "ai": {
            "configured": ai_configured,
            "model": MODEL,
            "summaries": "claude" if ai_configured and os.environ.get("AI_SUMMARIES") == "on" else "template",
        },
        "experiments": list(current_app.extensions.get("experiments", ())),
    })
