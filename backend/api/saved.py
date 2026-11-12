"""Saved events ("save for later"), kept on the account so they match on every device."""
from flask import Blueprint, current_app, g, jsonify

from api.events import _guarded

saved_bp = Blueprint("saved", __name__, url_prefix="/api/me/saved")


def _users():
    return current_app.extensions["user_repository"]


@saved_bp.get("")
def list_saved():
    user = _users().get(g.user.id)
    return jsonify({"event_ids": list(user.saved_event_ids) if user else []})


@saved_bp.put("/<event_id>")
def save(event_id):
    events = current_app.extensions["event_service"]

    def run():
        events.get_event(event_id)  # 404 for events that don't exist
        user = _users().set_saved(g.user.id, event_id, True, events.now(), email=g.user.email, name=g.user.name)
        return jsonify({"event_ids": user.saved_event_ids})
    return _guarded(run)


@saved_bp.delete("/<event_id>")
def unsave(event_id):
    # Works for deleted events too, so they can always be removed.
    events = current_app.extensions["event_service"]
    user = _users().set_saved(g.user.id, event_id, False, events.now(), email=g.user.email, name=g.user.name)
    return jsonify({"event_ids": user.saved_event_ids})
