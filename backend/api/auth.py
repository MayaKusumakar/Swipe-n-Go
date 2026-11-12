"""Sign-in endpoints, and the check that every /api request is signed in.

Every /api/* route needs `Authorization: Bearer <Google ID token>` from a
verified @ucdavis.edu account, except GET /api/auth/config (the app asks it
before signing in). /health and /tasks/* are not under /api.
"""
from dataclasses import replace

from flask import Blueprint, current_app, g, jsonify, request

from api.errors import error_response
from services.auth_service import ALLOWED_DOMAIN, AuthError, NotUCDavisError

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")

PUBLIC_PATHS = {"/api/auth/config"}


def require_signed_in_user():
    """Runs before every request (registered in main.py)."""
    if not request.path.startswith("/api/") or request.path in PUBLIC_PATHS or request.method == "OPTIONS":
        return None
    try:
        g.user = current_app.extensions["auth_service"].user_from_header(request.headers.get("Authorization"))
    except NotUCDavisError as e:
        return error_response(403, "ucdavis_only", str(e))
    except AuthError as e:
        return error_response(401, "unauthenticated", str(e))
    return None


@auth_bp.get("/config")
def config():
    return jsonify({
        "allowed_domain": ALLOWED_DOMAIN,
        "dev_sign_in": current_app.extensions["auth_service"].dev_mode,
    })


@auth_bp.post("/sign-in")
def sign_in():
    """Called once after signing in: saves the account and returns it."""
    user = g.user
    users = current_app.extensions["user_repository"]
    try:
        saved = users.record_sign_in(user.id, user.email, user.name, user.picture_url,
                                     current_app.extensions["event_service"].now())
    except Exception:  # noqa: BLE001 - the account is still valid; saving it can be retried
        current_app.logger.exception("Couldn't save the signed-in user")
        return jsonify(user.to_dict())
    return jsonify(saved.to_dict())


@auth_bp.get("/me")
def me():
    return jsonify(acting_user().to_dict())


MAX_DISPLAY_NAME = 60


@auth_bp.patch("/me")
def update_me():
    """Sets the name shown on your events and join requests (the name from your profile)."""
    body = request.get_json(silent=True)
    name = body.get("name") if isinstance(body, dict) else None
    if not isinstance(name, str) or not name.strip():
        return error_response(400, "invalid_name", "name must be a non-empty string")
    name = " ".join(name.split())
    if len(name) > MAX_DISPLAY_NAME:
        return error_response(400, "invalid_name", f"name must be at most {MAX_DISPLAY_NAME} characters")
    users = current_app.extensions["user_repository"]
    saved = users.set_display_name(g.user.id, name, current_app.extensions["event_service"].now(),
                                   email=g.user.email, name=g.user.name)
    return jsonify({"id": saved.id, "email": saved.email, "name": saved.shown_name,
                    "picture_url": saved.picture_url})


def acting_user():
    """The signed-in user, named the way they chose in the app (one read; only
    called where a name gets saved: posting an event or asking to join)."""
    try:
        saved = current_app.extensions["user_repository"].get(g.user.id)
    except Exception:  # noqa: BLE001 - fall back to the sign-in name
        current_app.logger.exception("Couldn't load the user's display name")
        return g.user
    if saved is not None and saved.display_name:
        return replace(g.user, name=saved.display_name)
    return g.user
