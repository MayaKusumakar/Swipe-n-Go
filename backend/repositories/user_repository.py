"""Signed-in users. Written once per sign-in (POST /api/auth/sign-in), never on
normal requests, so sign-in adds almost nothing to Datastore usage."""
import threading
from dataclasses import replace

from google.cloud import datastore

from models import USER_KIND, User


class UserRepository:
    def __init__(self, client=None, namespace=None):
        self._client = client
        self._namespace = namespace

    @property
    def client(self):
        if self._client is None:
            self._client = datastore.Client(namespace=self._namespace)
        return self._client

    def record_sign_in(self, user_id, email, name, picture_url, now):
        """Creates the user on first sign-in, otherwise refreshes their details."""
        key = self.client.key(USER_KIND, user_id)
        with self.client.transaction():
            existing = self.client.get(key)
            created_at = existing["created_at"] if existing is not None else now
            display_name = existing.get("display_name") if existing is not None else None
            user = User(id=user_id, email=email, name=name, picture_url=picture_url,
                        created_at=created_at, last_sign_in_at=now, display_name=display_name)
            entity = datastore.Entity(key=key)
            entity.update(user.to_entity_properties())
            self.client.put(entity)
        return user

    def get(self, user_id):
        entity = self.client.get(self.client.key(USER_KIND, user_id))
        return User.from_entity(entity) if entity is not None else None

    def set_display_name(self, user_id, display_name, now, email="", name=""):
        """Saves the name chosen in the app. Creates the user if they haven't been saved yet."""
        key = self.client.key(USER_KIND, user_id)
        with self.client.transaction():
            existing = self.client.get(key)
            user = (User.from_entity(existing) if existing is not None
                    else User(id=user_id, email=email, name=name, picture_url=None, created_at=now, last_sign_in_at=now))
            user = replace(user, display_name=display_name)
            entity = datastore.Entity(key=key)
            entity.update(user.to_entity_properties())
            self.client.put(entity)
        return user


class InMemoryUserRepository:
    """DEVELOPMENT ONLY (EVENT_STORE=memory) and tests."""

    def __init__(self):
        self._users = {}
        self._lock = threading.Lock()

    def record_sign_in(self, user_id, email, name, picture_url, now):
        with self._lock:
            existing = self._users.get(user_id)
            user = (replace(existing, email=email, name=name, picture_url=picture_url, last_sign_in_at=now)
                    if existing else User(user_id, email, name, picture_url, now, now))
            self._users[user_id] = user
        return user

    def get(self, user_id):
        with self._lock:
            return self._users.get(user_id)

    def set_display_name(self, user_id, display_name, now, email="", name=""):
        with self._lock:
            existing = self._users.get(user_id) or User(user_id, email, name, None, now, now)
            user = replace(existing, display_name=display_name)
            self._users[user_id] = user
        return user
