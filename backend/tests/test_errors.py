from conftest import FakeEventRepository, make_app, signed_in
from services.event_service import EventService


def test_unknown_route_returns_json_404(client):
    response = client.get("/api/nope")

    assert response.status_code == 404
    assert response.get_json()["error"]["code"] == "not_found"


def test_wrong_method_returns_json_405(client):
    response = client.delete("/api/events")

    assert response.status_code == 405
    assert response.get_json()["error"]["code"] == "method_not_allowed"


def test_unexpected_crash_returns_json_500():
    repository = FakeEventRepository()
    repository.error = RuntimeError("bug")
    response = signed_in(make_app(EventService(repository))).get("/api/events")

    assert response.status_code == 500
    assert response.get_json() == {
        "error": {"code": "internal_error", "message": "Something went wrong on the server"}
    }
