"""Datastore access for events. Route handlers never touch Datastore directly."""
from google.cloud import datastore
from google.cloud.datastore.query import PropertyFilter

from models import EVENT_KIND, Event


class EventRepository:
    def __init__(self, client=None, namespace=None):
        self._client = client
        self._namespace = namespace

    @property
    def client(self):
        # Created on first use so the app (and tests) can start without
        # Google Cloud credentials.
        if self._client is None:
            self._client = datastore.Client(namespace=self._namespace)
        return self._client

    def list_upcoming(self, now, limit):
        """Events starting at or after `now`, soonest first."""
        query = self.client.query(kind=EVENT_KIND)
        query.add_filter(filter=PropertyFilter("start_time", ">=", now))
        query.order = ["start_time"]
        return [Event.from_entity(entity) for entity in query.fetch(limit=limit)]

    def add(self, event):
        """Stores a new event. Returns False if one with the same id exists."""
        key = self.client.key(EVENT_KIND, event.id)
        with self.client.transaction():
            if self.client.get(key) is not None:
                return False
            entity = datastore.Entity(key=key, exclude_from_indexes=("description",))
            entity.update(event.to_entity_properties())
            self.client.put(entity)
        return True
