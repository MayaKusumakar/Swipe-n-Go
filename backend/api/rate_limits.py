"""Per-user request limits on /api routes (see services/rate_limiter.py)."""
from flask import current_app, g, request

from api.errors import error_response


def _wait(seconds):
    if seconds < 120:
        return f"{seconds} seconds"
    if seconds < 2 * 3600:
        return f"{round(seconds / 60)} minutes"
    return f"{round(seconds / 3600)} hours"


def enforce_rate_limits():
    """Runs before every request, after the sign-in check (registered in main.py).
    Only signed-in /api requests are counted; GET /api/auth/config and /health aren't."""
    user = g.get("user")
    if user is None or not request.path.startswith("/api/"):
        return None
    route = request.url_rule.rule if request.url_rule else request.path
    blocked = current_app.extensions["rate_limiter"].check(user.id, request.method, route)
    if blocked is None:
        return None
    limit, retry_after = blocked
    body, status = error_response(429, "rate_limited", f"{limit.message} Try again in {_wait(retry_after)}.")
    return body, status, {"Retry-After": str(retry_after)}
