from flask import Blueprint, current_app, jsonify, request

from api.errors import error_response
from api.planner_input import InvalidPlannerRequestError, parse_planner_request
from services.planner_service import PlannerUnavailableError

planner_bp = Blueprint("planner", __name__, url_prefix="/api/planner")


@planner_bp.post("")
def plan():
    try:
        query, now, interests, events = parse_planner_request(request.get_json(silent=True))
    except InvalidPlannerRequestError as e:
        return error_response(400, "invalid_planner_request", str(e))

    service = current_app.extensions["planner_service"]
    try:
        result = service.plan(query, now, interests, events)
    except PlannerUnavailableError as e:
        current_app.logger.warning("Planner unavailable: %s", e)
        return error_response(503, "ai_unavailable", str(e))

    return jsonify(result.to_dict())
