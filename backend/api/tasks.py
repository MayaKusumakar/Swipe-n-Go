"""Internal routes for scheduled work. Not part of the public API.

On App Engine only cron (cron.yaml) or, later, Cloud Tasks may call these:
App Engine sets X-Appengine-Cron / X-AppEngine-QueueName on those requests and
strips them from outside traffic, so they can't be faked. Locally (no GAE_ENV),
calls from this machine are allowed so the job can be run by hand with curl.
Cron sends GET, Cloud Tasks usually POST, so both are accepted.
"""
import os
from datetime import datetime, timezone

from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response

tasks_bp = Blueprint("tasks", __name__, url_prefix="/tasks")

_LOCAL_ADDRESSES = {"127.0.0.1", "::1"}


def _allowed():
    if os.environ.get("GAE_ENV"):
        return (request.headers.get("X-Appengine-Cron") == "true"
                or bool(request.headers.get("X-AppEngine-QueueName")))
    return request.remote_addr in _LOCAL_ADDRESSES


@tasks_bp.route("/summarize-stale", methods=["GET", "POST"])
def summarize_stale():
    if not _allowed():
        return error_response(403, "forbidden", "Only App Engine cron or Cloud Tasks can call this")
    written = current_app.extensions["summary_service"].summarize_stale(datetime.now(timezone.utc))
    return jsonify({"summarized": written})
