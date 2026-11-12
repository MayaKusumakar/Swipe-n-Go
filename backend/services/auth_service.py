"""Sign-in: only verified @ucdavis.edu Google accounts.

The app signs in with Google and sends the Google ID token as
`Authorization: Bearer <token>` on every request. The server checks it here,
on its own: the signature against Google's public keys (fetched at most once an
hour and cached), the audience (our OAuth client IDs), the issuer, expiry, and
that the account is a verified @ucdavis.edu Google Workspace account.

Free: Google Sign-In costs nothing, and checking a token needs no Datastore read
and no paid API.

Dev sign-in (DEV_SIGN_IN=on, never on App Engine): accepts "dev:<email>:<name>"
tokens so the app can be tried in the simulator before the Google client IDs
exist. The email must still end in @ucdavis.edu.
"""
import os
import threading
import time
from dataclasses import dataclass

import requests
from google.auth import jwt

ALLOWED_DOMAIN = "ucdavis.edu"
GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v1/certs"
CERTS_MAX_AGE = 3600           # Google rotates keys roughly daily
CERTS_MIN_REFRESH = 300        # on an unknown key, refetch at most every 5 minutes
CLOCK_SKEW_SECONDS = 30
DEV_PREFIX = "dev:"


class AuthError(Exception):
    """No token, or one that isn't a valid Google ID token for this app (401)."""


class NotUCDavisError(Exception):
    """A real Google account, but not a verified @ucdavis.edu one (403)."""


@dataclass(frozen=True)
class SignedInUser:
    id: str              # Google's stable account id ("sub"); "dev-<email>" in dev mode
    email: str
    name: str
    picture_url: str | None = None

    def to_dict(self):
        return {"id": self.id, "email": self.email, "name": self.name, "picture_url": self.picture_url}


def _is_ucdavis(email):
    local, _, domain = email.lower().rpartition("@")
    return bool(local) and domain == ALLOWED_DOMAIN


def dev_sign_in_enabled():
    return os.environ.get("DEV_SIGN_IN") == "on" and not os.environ.get("GAE_ENV")


class GoogleCerts:
    """Google's public signing keys, cached in memory."""

    def __init__(self, fetch=None, clock=time.monotonic):
        self._fetch = fetch or (lambda: requests.get(GOOGLE_CERTS_URL, timeout=5).json())
        self._clock = clock
        self._certs, self._fetched_at = None, None
        self._lock = threading.Lock()

    def get(self, force=False):
        with self._lock:
            age = None if self._fetched_at is None else self._clock() - self._fetched_at
            stale = age is None or age >= CERTS_MAX_AGE or (force and age >= CERTS_MIN_REFRESH)
            if stale:
                try:
                    self._certs, self._fetched_at = self._fetch(), self._clock()
                except (requests.RequestException, ValueError) as e:
                    if self._certs is None:
                        raise AuthError("Couldn't check the sign-in with Google right now") from e
            return self._certs


class AuthService:
    def __init__(self, client_ids=None, certs=None, dev_mode=None):
        if client_ids is None:
            client_ids = [c.strip() for c in os.environ.get("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]
        self._client_ids = set(client_ids)
        self._certs = certs or GoogleCerts()
        self._dev_mode = dev_sign_in_enabled() if dev_mode is None else dev_mode

    @property
    def dev_mode(self):
        return self._dev_mode

    def user_from_header(self, header):
        if not header or not header.startswith("Bearer "):
            raise AuthError("Sign in with your @ucdavis.edu Google account")
        token = header[len("Bearer "):].strip()
        if token.startswith(DEV_PREFIX):
            return self._dev_user(token)
        return self._google_user(token)

    def _dev_user(self, token):
        if not self._dev_mode:
            raise AuthError("Dev sign-in is off on this server")
        email, _, name = token[len(DEV_PREFIX):].partition(":")
        email = email.strip().lower()
        if not _is_ucdavis(email):
            raise NotUCDavisError("Only @ucdavis.edu accounts can use Swipe-n-Go")
        return SignedInUser(id="dev-" + email, email=email, name=name.strip() or email.split("@")[0])

    def _google_user(self, token):
        if not self._client_ids:
            raise AuthError("Google sign-in isn't set up on this server (no GOOGLE_CLIENT_IDS)")
        claims = self._decode(token)
        if claims.get("iss") not in GOOGLE_ISSUERS or claims.get("aud") not in self._client_ids:
            raise AuthError("This sign-in wasn't made for Swipe-n-Go")
        email = (claims.get("email") or "").lower()
        verified = claims.get("email_verified") in (True, "true")
        if not (verified and claims.get("hd") == ALLOWED_DOMAIN and _is_ucdavis(email)):
            raise NotUCDavisError("Only @ucdavis.edu accounts can use Swipe-n-Go")
        return SignedInUser(id=claims["sub"], email=email, name=claims.get("name") or email.split("@")[0],
                            picture_url=claims.get("picture"))

    def _decode(self, token):
        for force in (False, True):
            try:
                return jwt.decode(token, certs=self._certs.get(force=force),
                                  clock_skew_in_seconds=CLOCK_SKEW_SECONDS)
            except ValueError as e:
                # An unknown key id may mean Google rotated keys: refetch once.
                if force or "not found" not in str(e).lower():
                    raise AuthError("Your sign-in expired or isn't valid. Sign in again.") from e
        raise AuthError("Your sign-in isn't valid. Sign in again.")
