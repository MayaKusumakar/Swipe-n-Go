"""Datastore access for events. Route handlers never touch Datastore directly."""
from google.cloud import datastore
from google.cloud.datastore.query import PropertyFilter

from models import ATTENDEE_KIND, EVENT_KIND, Attendee, Event


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

    def get(self, event_id):
        entity = self.client.get(self.client.key(EVENT_KIND, event_id))
        return Event.from_entity(entity) if entity is not None else None

    # Attendees are stored as child entities of their event.

    def _attendee_key(self, event_id, attendee_id):
        return self.client.key(EVENT_KIND, event_id, ATTENDEE_KIND, attendee_id)

    def list_attendees(self, event_id):
        query = self.client.query(kind=ATTENDEE_KIND, ancestor=self.client.key(EVENT_KIND, event_id))
        attendees = [Attendee.from_entity(entity) for entity in query.fetch()]
        return sorted(attendees, key=lambda a: a.created_at)

    def get_attendee(self, event_id, attendee_id):
        entity = self.client.get(self._attendee_key(event_id, attendee_id))
        return Attendee.from_entity(entity) if entity is not None else None

    def save_attendee(self, attendee):
        entity = datastore.Entity(key=self._attendee_key(attendee.event_id, attendee.id))
        entity.update(attendee.to_entity_properties())
        self.client.put(entity)

    def delete_attendee(self, event_id, attendee_id):
        self.client.delete(self._attendee_key(event_id, attendee_id))
