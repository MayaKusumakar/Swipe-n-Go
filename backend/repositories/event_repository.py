"""Datastore access for events. Route handlers never touch Datastore directly."""
from google.cloud import datastore
from google.cloud.datastore.query import PropertyFilter

from models import (APPROVED, ATTENDEE_KIND, CANCELLED_KIND, COVER_KIND, EVENT_KIND, MESSAGE_KIND,
                    UNINDEXED_EVENT_PROPERTIES, Attendee, Cancellation, Event, Message)

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

    def delete_event(self, event_id, cancelled_at):
        """Deletes the event with its attendees and cover, leaving a Cancellation for the people who
        joined or asked to join. Returns the Cancellation, or None if there was no such event."""
        event_key = self.client.key(EVENT_KIND, event_id)
        entity = self.client.get(event_key)
        if entity is None:
            return None
        keys = self._child_keys(ATTENDEE_KIND, event_key)
        cancellation = Cancellation.for_event(Event.from_entity(entity), [k.id_or_name for k in keys], cancelled_at)
        if cancellation.attendee_ids:
            notice = datastore.Entity(key=self.client.key(CANCELLED_KIND, event_id), exclude_from_indexes=("title",))
            notice.update(cancellation.to_entity_properties())
            self.client.put(notice)
        keys += self._child_keys(MESSAGE_KIND, event_key) + [self.client.key(COVER_KIND, event_id), event_key]
        # delete_multi takes at most 500 keys per call; the event itself goes last.
        for start in range(0, len(keys), 500):
            self.client.delete_multi(keys[start:start + 500])
        return cancellation

    def _child_keys(self, kind, event_key):
        query = self.client.query(kind=kind, ancestor=event_key)
        query.keys_only()
        return [entity.key for entity in query.fetch()]

    def list_cancellations_for(self, user_id, limit):
        """Deleted events `user_id` had joined or asked to join, most recently cancelled first."""
        query = self.client.query(kind=CANCELLED_KIND)
        query.add_filter(filter=PropertyFilter("attendee_ids", "=", user_id))
        found = [Cancellation.from_entity(e) for e in query.fetch(limit=200)]
        return sorted(found, key=lambda c: c.cancelled_at, reverse=True)[:limit]

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

    def rename_host(self, host_id, host_name):
        """Puts the host's new name on every event they posted. Returns how many changed."""
        query = self.client.query(kind=EVENT_KIND)
        query.add_filter(filter=PropertyFilter("host_id", "=", host_id))
        changed = [entity for entity in query.fetch() if entity.get("host_name") != host_name]
        for entity in changed:
            entity["host_name"] = host_name
        # put_multi takes at most 500 entities per call.
        for start in range(0, len(changed), 500):
            self.client.put_multi(changed[start:start + 500])
        return len(changed)

    def save_cover(self, event_id, data, image_url):
        """Stores the cover JPEG (under Datastore's 1 MB entity limit) and points the event at it."""
        event_key = self.client.key(EVENT_KIND, event_id)
        with self.client.transaction():
            event = self.client.get(event_key)
            if event is None:
                return False
            cover = datastore.Entity(key=self.client.key(COVER_KIND, event_id), exclude_from_indexes=("data",))
            cover["data"] = data
            event["image_url"] = image_url
            self.client.put_multi([cover, event])
        return True

    def get_cover(self, event_id):
        entity = self.client.get(self.client.key(COVER_KIND, event_id))
        return entity["data"] if entity is not None else None

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

    def set_check_in(self, event_id, attendee_id, checked_in):
        key = self._attendee_key(event_id, attendee_id)
        with self.client.transaction():
            entity = self.client.get(key)
            if entity is None:
                return None
            attendee = Attendee.from_entity(entity)
            if attendee.status == APPROVED and attendee.checked_in != checked_in:
                attendee.checked_in = checked_in
                entity["checked_in"] = checked_in
                self.client.put(entity)
        return attendee

    def set_attendance(self, event_id, attendee_id, attended, feedback, answered_at):
        """Stores a guest's "Did you attend?" answer and feedback. None if there's no such attendee."""
        key = self._attendee_key(event_id, attendee_id)
        with self.client.transaction():
            entity = self.client.get(key)
            if entity is None:
                return None
            entity.exclude_from_indexes = set(entity.exclude_from_indexes) | {"feedback"}
            entity.update({"attended": attended, "feedback": feedback, "feedback_at": answered_at})
            self.client.put(entity)
        return Attendee.from_entity(entity)

    def save_attendee(self, attendee):
        entity = datastore.Entity(key=self._attendee_key(attendee.event_id, attendee.id))
        entity.update(attendee.to_entity_properties())
        self.client.put(entity)

    def delete_attendee(self, event_id, attendee_id):
        self.client.delete(self._attendee_key(event_id, attendee_id))

    # Group chat messages are child entities of their event, keyed so key order is time order.

    def add_message(self, message):
        """Stores `message` unless one with the same client_id is already in this chat.
        Returns (stored message, created). None if the event is gone."""
        event_key = self.client.key(EVENT_KIND, message.event_id)
        with self.client.transaction():
            if self.client.get(event_key) is None:
                return None
            if message.client_id is not None:
                query = self.client.query(kind=MESSAGE_KIND, ancestor=event_key)
                query.add_filter(filter=PropertyFilter("client_id", "=", message.client_id))
                existing = list(query.fetch(limit=1))
                if existing:
                    return Message.from_entity(existing[0]), False
            entity = datastore.Entity(key=self.client.key(EVENT_KIND, message.event_id, MESSAGE_KIND, message.id),
                                      exclude_from_indexes=("text", "sender_name"))
            entity.update(message.to_entity_properties())
            self.client.put(entity)
        return message, True

    def list_messages(self, event_id, after_id, limit):
        """Up to `limit` messages after the one with id `after_id` (from the start if None), oldest first."""
        event_key = self.client.key(EVENT_KIND, event_id)
        query = self.client.query(kind=MESSAGE_KIND, ancestor=event_key)
        if after_id is not None:
            query.add_filter(filter=PropertyFilter(
                "__key__", ">", self.client.key(EVENT_KIND, event_id, MESSAGE_KIND, after_id)))
        query.order = ["__key__"]
        return [Message.from_entity(entity) for entity in query.fetch(limit=limit)]
