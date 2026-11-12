"""Sign-in: only verified @ucdavis.edu Google accounts get in.

Real Google-style tokens are signed here with a throwaway RSA key, so the full
check (signature, issuer, audience, expiry, domain) runs without the network.
"""
import time

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from google.auth import crypt, jwt

from conftest import FIXED_NOW, FakeEventRepository, as_user
from main import create_app
from repositories.user_repository import InMemoryUserRepository
from services.auth_service import (
    AuthError, AuthService, GoogleCerts, NotUCDavisError, dev_sign_in_enabled,
)
from services.event_service import EventService

CLIENT_ID = "123-ios.apps.googleusercontent.com"


def _key():
    private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                        serialization.NoEncryption()).decode()
    public_pem = private.public_key().public_bytes(serialization.Encoding.PEM,
                                                   serialization.PublicFormat.SubjectPublicKeyInfo).decode()
    return private_pem, public_pem


PRIVATE_PEM, PUBLIC_PEM = _key()
OTHER_PRIVATE_PEM, _ = _key()


def google_token(key_id="k1", private_pem=PRIVATE_PEM, **overrides):
    now = int(time.time())
    claims = {
        "iss": "https://accounts.google.com", "aud": CLIENT_ID, "sub": "1093",
        "email": "maya@ucdavis.edu", "email_verified": True, "hd": "ucdavis.edu",
        "name": "Maya Lee", "picture": "https://example.com/p.png", "iat": now, "exp": now + 3600,
    }
    claims.update(overrides)
    claims = {k: v for k, v in claims.items() if v is not None}
    signer = crypt.RSASigner.from_string(private_pem, key_id=key_id)
    return jwt.encode(signer, claims).decode()


class Fetcher:
    def __init__(self, *responses):
        self.responses, self.calls = list(responses), 0

    def __call__(self):
        self.calls += 1
        return self.responses[min(self.calls, len(self.responses)) - 1]


def service(fetch=None, dev_mode=False, clock=time.monotonic):
    certs = GoogleCerts(fetch=fetch or Fetcher({"k1": PUBLIC_PEM}), clock=clock)
    return AuthService(client_ids=[CLIENT_ID], certs=certs, dev_mode=dev_mode)


def check(token, **kwargs):
    return service(**kwargs).user_from_header(f"Bearer {token}")


def test_valid_ucdavis_account():
    user = check(google_token())
    assert (user.id, user.email, user.name) == ("1093", "maya@ucdavis.edu", "Maya Lee")


@pytest.mark.parametrize("overrides", [
    {"email": "maya@gmail.com", "hd": None},                 # personal Gmail
    {"email": "maya@ucdavis.edu", "hd": None},               # not the UC Davis Workspace
    {"email": "maya@stanford.edu", "hd": "stanford.edu"},    # another school
    {"email": "maya@health.ucdavis.edu"},                    # not exactly @ucdavis.edu
    {"email_verified": False},
])
def test_other_accounts_are_refused(overrides):
    with pytest.raises(NotUCDavisError):
        check(google_token(**overrides))


@pytest.mark.parametrize("token", [
    google_token(aud="someone-elses-app.apps.googleusercontent.com"),
    google_token(iss="https://evil.example.com"),
    google_token(iat=int(time.time()) - 7200, exp=int(time.time()) - 3600),   # expired
    google_token(private_pem=OTHER_PRIVATE_PEM),                             # forged signature
    "not-a-jwt",
])
def test_invalid_tokens_are_refused(token):
    with pytest.raises(AuthError):
        check(token)


@pytest.mark.parametrize("header", [None, "", "Basic abc", "Bearer "])
def test_missing_or_malformed_header(header):
    with pytest.raises(AuthError):
        service().user_from_header(header)


def test_no_client_ids_configured_refuses_google_tokens():
    with pytest.raises(AuthError, match="GOOGLE_CLIENT_IDS"):
        AuthService(client_ids=[], certs=GoogleCerts(fetch=Fetcher({}))).user_from_header(f"Bearer {google_token()}")


def test_certs_are_fetched_once_and_cached():
    fetch = Fetcher({"k1": PUBLIC_PEM})
    auth = service(fetch=fetch)
    for _ in range(5):
        auth.user_from_header(f"Bearer {google_token()}")
    assert fetch.calls == 1


def test_rotated_key_triggers_one_refetch():
    clock = [0.0]
    fetch = Fetcher({"old": PUBLIC_PEM}, {"new": PUBLIC_PEM})
    auth = service(fetch=fetch, clock=lambda: clock[0])
    auth.user_from_header(f"Bearer {google_token(key_id='old')}")

    clock[0] = 600  # Google started signing with a new key; past the 5-minute refetch gap
    assert auth.user_from_header(f"Bearer {google_token(key_id='new')}").id == "1093"
    assert fetch.calls == 2


def test_unknown_key_refetch_is_rate_limited():
    fetch = Fetcher({"old": PUBLIC_PEM})
    auth = service(fetch=fetch, clock=lambda: 0.0)
    auth.user_from_header(f"Bearer {google_token(key_id='old')}")
    with pytest.raises(AuthError):
        auth.user_from_header(f"Bearer {google_token(key_id='unknown')}")
    assert fetch.calls == 1


# Dev sign-in, for the simulator before Google client IDs exist.

def test_dev_tokens_only_when_dev_mode_is_on():
    with pytest.raises(AuthError):
        service(dev_mode=False).user_from_header("Bearer dev:maya@ucdavis.edu:Maya")
    user = service(dev_mode=True).user_from_header("Bearer dev:Maya@UCDavis.edu:Maya")
    assert (user.id, user.email, user.name) == ("dev-maya@ucdavis.edu", "maya@ucdavis.edu", "Maya")


@pytest.mark.parametrize("email", ["maya@gmail.com", "@ucdavis.edu", "maya@health.ucdavis.edu"])
def test_dev_tokens_still_need_ucdavis(email):
    with pytest.raises(NotUCDavisError):
        service(dev_mode=True).user_from_header(f"Bearer dev:{email}:Maya")


def test_dev_sign_in_is_never_on_app_engine(monkeypatch):
    monkeypatch.setenv("DEV_SIGN_IN", "on")
    monkeypatch.delenv("GAE_ENV", raising=False)
    assert dev_sign_in_enabled() is True
    monkeypatch.setenv("GAE_ENV", "standard")
    assert dev_sign_in_enabled() is False


# Through the HTTP API.

@pytest.fixture
def app_parts():
    users = InMemoryUserRepository()
    app = create_app(EventService(FakeEventRepository(), clock=lambda: FIXED_NOW),
                     auth_service=service(dev_mode=True), user_repository=users)
    return app.test_client(), users


@pytest.mark.parametrize("method,path", [
    ("GET", "/api/events"), ("POST", "/api/events"), ("GET", "/api/events/nearby?lat=38.5&lng=-121.7"),
    ("GET", "/api/events/recommended?interests=run"), ("POST", "/api/events/x/attendees"),
    ("GET", "/api/events/x/location"), ("POST", "/api/planner"), ("GET", "/api/auth/me"),
])
def test_every_api_route_needs_sign_in(app_parts, method, path):
    client, _ = app_parts
    response = client.open(path, method=method)
    assert response.status_code == 401
    assert response.get_json()["error"]["code"] == "unauthenticated"


def test_wrong_school_gets_403(app_parts):
    client, _ = app_parts
    token = google_token(email="maya@gmail.com", hd=None)
    response = client.get("/api/events", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 403
    assert response.get_json()["error"]["code"] == "ucdavis_only"


def test_public_routes(app_parts):
    client, _ = app_parts
    assert client.get("/health").status_code == 200
    assert client.get("/api/auth/config").get_json() == {"allowed_domain": "ucdavis.edu", "dev_sign_in": True}


def test_sign_in_saves_the_account_and_me_returns_it(app_parts):
    client, users = app_parts
    headers = {"Authorization": f"Bearer {google_token()}"}

    first = client.post("/api/auth/sign-in", headers=headers).get_json()
    created = users.get("1093").created_at
    client.post("/api/auth/sign-in", headers=headers)

    assert first == {"id": "1093", "email": "maya@ucdavis.edu", "name": "Maya Lee",
                     "picture_url": "https://example.com/p.png", "display_name": None}
    assert users.get("1093").created_at == created
    assert client.get("/api/auth/me", headers=as_user("Hana")).get_json()["email"] == "hana@ucdavis.edu"
