import base64
import binascii
from datetime import datetime

from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response
from services.claude_call import AIUnavailableError

flyers_bp = Blueprint("flyers", __name__, url_prefix="/api/flyers")

MAX_IMAGE_BYTES = 5 * 1024 * 1024       # Claude's per-image limit; the app sends ~0.5 MB
MAX_OCR_TEXT = 4000
# Checked against the bytes themselves, not just the label the client sends.
SIGNATURES = {"image/jpeg": b"\xff\xd8\xff", "image/png": b"\x89PNG\r\n\x1a\n"}


class InvalidFlyerError(ValueError):
    pass


def _parse(body):
    if not isinstance(body, dict):
        raise InvalidFlyerError("request body must be a JSON object")

    media_type = body.get("media_type")
    if media_type not in SIGNATURES:
        raise InvalidFlyerError("media_type must be image/jpeg or image/png")
    try:
        image = base64.b64decode(body.get("image") or "", validate=True)
    except (binascii.Error, TypeError, ValueError):
        raise InvalidFlyerError("image must be base64") from None
    if not image:
        raise InvalidFlyerError("image is required")
    if len(image) > MAX_IMAGE_BYTES:
        raise InvalidFlyerError("image must be under 5 MB")
    if not image.startswith(SIGNATURES[media_type]):
        raise InvalidFlyerError(f"image is not a valid {media_type.split('/')[1].upper()} file")

    now = body.get("now")
    try:
        now = datetime.fromisoformat(str(now).replace("Z", "+00:00"))
    except ValueError:
        raise InvalidFlyerError("now must be an ISO-8601 date-time") from None
    if now.tzinfo is None:
        raise InvalidFlyerError("now must include a UTC offset")

    ocr_text = body.get("ocr_text") or ""
    if not isinstance(ocr_text, str):
        raise InvalidFlyerError("ocr_text must be a string")
    return image, media_type, now, ocr_text[:MAX_OCR_TEXT]


@flyers_bp.post("/read")
def read_flyer():
    try:
        image, media_type, now, ocr_text = _parse(request.get_json(silent=True))
    except InvalidFlyerError as e:
        return error_response(400, "invalid_flyer_request", str(e))

    try:
        reading = current_app.extensions["flyer_service"].read(image, media_type, now, ocr_text)
    except AIUnavailableError as e:
        current_app.logger.warning("Flyer reader unavailable: %s", e)
        return error_response(503, "ai_unavailable", str(e))
    return jsonify(reading.to_dict())
