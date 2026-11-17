from conftest import FIXED_NOW, make_app, signed_in
from services.event_service import EventService
from services.rate_limiter import DAY, MINUTE, Limit, RateLimiter
from test_create_event_api import VALID_BODY

START = 20833 * DAY  # exactly midnight UTC, so day windows start here


class FakeClock:
    def __init__(self, now=START):
        self.now = now

    def __call__(self):
        return self.now


def limiter(*limits, clock=None):
    return RateLimiter(limits=limits, clock=clock or FakeClock())


def app_with(rate_limiter, repository):
    return make_app(EventService(repository, clock=lambda: FIXED_NOW), rate_limiter=rate_limiter)


# MARK: RateLimiter


def test_allows_up_to_the_limit_then_refuses_until_the_window_resets():
    clock = FakeClock()
    limit = Limit("requests", 3, MINUTE, "Too many.")
    rate_limiter = limiter(limit, clock=clock)

    assert [rate_limiter.check("u1", "GET", "/api/events") for _ in range(3)] == [None] * 3
    clock.now += 20
    assert rate_limiter.check("u1", "GET", "/api/events") == (limit, 40)

    clock.now += 40
    assert rate_limiter.check("u1", "GET", "/api/events") is None


def test_each_user_has_their_own_count():
    rate_limiter = limiter(Limit("requests", 1, MINUTE, "Too many."))

    assert rate_limiter.check("u1", "GET", "/api/events") is None
    assert rate_limiter.check("u2", "GET", "/api/events") is None
    assert rate_limiter.check("u1", "GET", "/api/events") is not None


def test_route_limits_only_count_their_route_and_method():
    rate_limiter = limiter(Limit("new_events", 1, DAY, "Too many.", method="POST", route="/api/events"))

    assert rate_limiter.check("u1", "POST", "/api/events") is None
    assert rate_limiter.check("u1", "GET", "/api/events") is None
    assert rate_limiter.check("u1", "POST", "/api/planner") is None
    assert rate_limiter.check("u1", "POST", "/api/events") is not None


def test_refused_requests_do_not_use_up_other_limits():
    general = Limit("requests", 10, MINUTE, "Too many.")
    strict = Limit("planner", 1, MINUTE, "Busy.", method="POST", route="/api/planner")
    rate_limiter = limiter(general, strict)

    rate_limiter.check("u1", "POST", "/api/planner")
    for _ in range(5):
        assert rate_limiter.check("u1", "POST", "/api/planner")[0] is strict
    # Only the one allowed request counted toward the general limit: 9 left.
    assert [rate_limiter.check("u1", "GET", "/api/events") for _ in range(9)] == [None] * 9
    assert rate_limiter.check("u1", "GET", "/api/events")[0] is general


# MARK: API


def test_api_answers_429_with_retry_after(repository):
    rate_limiter = limiter(Limit("requests", 2, MINUTE, "You're making requests too quickly."))
    client = signed_in(app_with(rate_limiter, repository))

    assert client.get("/api/events").status_code == 200
    assert client.get("/api/events").status_code == 200
    response = client.get("/api/events")

    assert response.status_code == 429
    assert response.headers["Retry-After"] == "60"
    error = response.get_json()["error"]
    assert error["code"] == "rate_limited"
    assert error["message"] == "You're making requests too quickly. Try again in 60 seconds."


def test_other_users_and_unlimited_paths_are_not_affected(repository):
    rate_limiter = limiter(Limit("requests", 1, MINUTE, "Too many."))
    app = app_with(rate_limiter, repository)
    avery, blake = signed_in(app, "Avery"), signed_in(app, "Blake")

    assert avery.get("/api/events").status_code == 200
    assert avery.get("/api/events").status_code == 429
    assert blake.get("/api/events").status_code == 200
    assert avery.get("/health").status_code == 200
    assert avery.get("/api/auth/config").status_code == 200


def test_requests_without_sign_in_get_401_not_429(repository):
    rate_limiter = limiter(Limit("requests", 1, MINUTE, "Too many."))
    client = app_with(rate_limiter, repository).test_client()

    assert [client.get("/api/events").status_code for _ in range(3)] == [401] * 3


def test_default_limits_cap_new_events_per_day(repository):
    clock = FakeClock()
    client = signed_in(app_with(RateLimiter(clock=clock), repository))

    for _ in range(20):
        assert client.post("/api/events", json=VALID_BODY).status_code == 201
    response = client.post("/api/events", json=VALID_BODY)

    assert response.status_code == 429
    assert response.get_json()["error"]["message"] == (
        "You've created the most events allowed today (20). Try again in 24 hours.")
    assert client.get("/api/events").status_code == 200

    clock.now += DAY
    assert client.post("/api/events", json=VALID_BODY).status_code == 201


def test_default_limits_cover_the_claude_and_upload_routes():
    rate_limiter = RateLimiter(clock=FakeClock())

    for _ in range(5):
        assert rate_limiter.check("u1", "POST", "/api/flyers/read") is None
    assert rate_limiter.check("u1", "POST", "/api/flyers/read")[0].name == "flyer_reads"

    for _ in range(20):
        assert rate_limiter.check("u1", "POST", "/api/experimental/events/parse") is None
    assert rate_limiter.check("u1", "POST", "/api/experimental/events/parse")[0].name == "event_parse_daily"

    for _ in range(30):
        assert rate_limiter.check("u1", "PUT", "/api/events/<event_id>/cover") is None
    assert rate_limiter.check("u1", "PUT", "/api/events/<event_id>/cover")[0].name == "cover_uploads"
