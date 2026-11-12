"""Datastore access for events. Route handlers never touch Datastore directly."""
from google.cloud import datastore
from google.cloud.datastore.query import PropertyFilter

from models import ATTENDEE_KIND, EVENT_KIND, UNINDEXED_EVENT_PROPERTIES, Attendee, Event

# Sorts after every geohash character, so [prefix, prefix + "~") is "starts with prefix".
_PREFIX_END = "~"


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
            entity = datastore.Entity(key=key, exclude_from_indexes=UNINDEXED_EVENT_PROPERTIES)
            entity.update(event.to_entity_properties())
            self.client.put(entity)
        return True

    def get(self, event_id):
        entity = self.client.get(self.client.key(EVENT_KIND, event_id))
        return Event.from_entity(entity) if entity is not None else None

    def list_in_geohash_cells(self, prefixes):
        """Events whose geohash starts with any of `prefixes` (past ones too)."""
        events = {}
        for prefix in prefixes:
            query = self.client.query(kind=EVENT_KIND)
            query.add_filter(filter=PropertyFilter("geohash", ">=", prefix))
            query.add_filter(filter=PropertyFilter("geohash", "<", prefix + _PREFIX_END))
            for entity in query.fetch():
                event = Event.from_entity(entity)
                events[event.id] = event
        return list(events.values())

    def list_stale_summaries(self, limit):
        query = self.client.query(kind=EVENT_KIND)
        query.add_filter(filter=PropertyFilter("summary_stale", "=", True))
        return [Event.from_entity(entity) for entity in query.fetch(limit=limit)]

    def save_summary(self, event_id, summary, updated_at, attendee_count):
        """Stores a summary. It stays stale if attendance changed while it was written."""
        key = self.client.key(EVENT_KIND, event_id)
        with self.client.transaction():
            entity = self.client.get(key)
            if entity is None:
                return
            entity["summary"] = summary
            entity["summary_updated_at"] = updated_at
            entity["summary_stale"] = entity.get("attendee_count", 0) != attendee_count
            self.client.put(entity)

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

    def update_attendance(self, event_id, attendee, delta, delete=False):
        """In one transaction: save (or delete) `attendee` and add `delta` to the
        event's attendee_count, so the two never disagree.

        Returns None if the event is gone, False (changing nothing) if delta > 0
        and the event is full, otherwise True.
        """
        event_key = self.client.key(EVENT_KIND, event_id)
        with self.client.transaction():
            entity = self.client.get(event_key)
            if entity is None:
                return None
            event = Event.from_entity(entity)
            if delta > 0 and event.is_full:
                return False
            entity["attendee_count"] = max(0, event.attendee_count + delta)
            if delta:
                entity["summary_stale"] = True
            self.client.put(entity)
            key = self._attendee_key(event_id, attendee.id)
            if delete:
                self.client.delete(key)
            else:
                attendee_entity = datastore.Entity(key=key)
                attendee_entity.update(attendee.to_entity_properties())
                self.client.put(attendee_entity)
        return True

    def save_attendee(self, attendee):
        entity = datastore.Entity(key=self._attendee_key(attendee.event_id, attendee.id))
        entity.update(attendee.to_entity_properties())
        self.client.put(entity)

    def delete_attendee(self, event_id, attendee_id):
        self.client.delete(self._attendee_key(event_id, attendee_id))
