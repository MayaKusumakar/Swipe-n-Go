"""Shared JSON error format: {"error": {"code": ..., "message": ...}}."""
from flask import jsonify
from werkzeug.exceptions import HTTPException, InternalServerError


def error_response(status, code, message):
    return jsonify({"error": {"code": code, "message": message}}), status


def register_error_handlers(app):
    """Unknown routes, wrong methods, and crashes also answer in the JSON format."""

    @app.errorhandler(HTTPException)
    def handle_http_error(e):
        code = (e.name or "error").lower().replace(" ", "_")
        return error_response(e.code, code, e.description)

    @app.errorhandler(InternalServerError)
    def handle_internal_error(e):
        return error_response(500, "internal_error", "Something went wrong on the server")
