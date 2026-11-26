"""DEVELOPMENT ONLY: event store held in memory (EVENT_STORE=memory).

Lets the app be demoed locally before a GCP project or Datastore emulator is
set up. Same interface as EventRepository. Events added while the server runs
are lost when it stops.
"""
import threading
from dataclasses import replace

from models import APPROVED, Cancellation


class InMemoryEventRepository:
    def __init__(self, events):
        self._events = sorted(events, key=lambda event: event.start_time)
        self._lock = threading.Lock()
        self._attendees = {}  # (event_id, attendee_id) -> Attendee
        self._covers = {}     # event_id -> JPEG bytes
        self._cancellations = {}  # event_id -> Cancellation
        self._messages = {}  # event_id -> [Message], oldest first

    def list_upcoming(self, now, limit):
        with self._lock:
            return [event for event in self._events if event.start_time >= now][:limit]

    def add(self, event):
        with self._lock:
            if any(existing.id == event.id for existing in self._events):
                return False
            self._events.append(event)
            self._events.sort(key=lambda e: e.start_time)
        return True

    def get(self, event_id):
        with self._lock:
            return next((event for event in self._events if event.id == event_id), None)

    def delete_event(self, event_id, cancelled_at):
        with self._lock:
            event = self._find(event_id)
            if event is None:
                return None
            guests = [attendee_id for (eid, attendee_id) in self._attendees if eid == event_id]
            cancellation = Cancellation.for_event(event, guests, cancelled_at)
            if guests:
                self._cancellations[event_id] = cancellation
            self._events = [e for e in self._events if e.id != event_id]
            self._attendees = {key: a for key, a in self._attendees.items() if key[0] != event_id}
            self._covers.pop(event_id, None)
            self._messages.pop(event_id, None)
        return cancellation

    def list_cancellations_for(self, user_id, limit):
        with self._lock:
            found = [c for c in self._cancellations.values() if user_id in c.attendee_ids]
        return sorted(found, key=lambda c: c.cancelled_at, reverse=True)[:limit]

    def rename_host(self, host_id, host_name):
        with self._lock:
            changed = [e for e in self._events if e.host_id == host_id and e.host_name != host_name]
            for event in changed:
                event.host_name = host_name
        return len(changed)

    def save_cover(self, event_id, data, image_url):
        with self._lock:
            event = self._find(event_id)
            if event is None:
                return False
            self._covers[event_id] = data
            event.image_url = image_url
        return True

    def get_cover(self, event_id):
        with self._lock:
            return self._covers.get(event_id)

    def list_in_geohash_cells(self, prefixes):
        with self._lock:
            return [event for event in self._events
                    if event.geohash and event.geohash.startswith(tuple(prefixes))]

    def list_stale_summaries(self, limit):
        with self._lock:
            return [event for event in self._events if event.summary_stale][:limit]

    def save_summary(self, event_id, summary, updated_at, attendee_count):
        with self._lock:
            event = self._find(event_id)
            if event is None:
                return
            event.summary = summary
            event.summary_updated_at = updated_at
            event.summary_stale = event.attendee_count != attendee_count

    def update_attendance(self, event_id, attendee, delta, delete=False):
        """Same contract as EventRepository.update_attendance."""
        with self._lock:
            event = self._find(event_id)
            if event is None:
                return None
            if delta > 0 and event.is_full:
                return False
            event.attendee_count = max(0, event.attendee_count + delta)
            if delta:
                event.summary_stale = True
            if delete:
                self._attendees.pop((event_id, attendee.id), None)
            else:
                self._attendees[(event_id, attendee.id)] = attendee
        return True

    def _find(self, event_id):
        return next((event for event in self._events if event.id == event_id), None)

    def list_attendees(self, event_id):
        with self._lock:
            attendees = [a for (eid, _), a in self._attendees.items() if eid == event_id]
        return sorted(attendees, key=lambda a: a.created_at)

    def get_attendee(self, event_id, attendee_id):
        with self._lock:
            return self._attendees.get((event_id, attendee_id))

    def set_check_in(self, event_id, attendee_id, checked_in):
        with self._lock:
            key = (event_id, attendee_id)
            attendee = self._attendees.get(key)
            if attendee is not None and attendee.status == APPROVED:
                attendee = replace(attendee, checked_in=checked_in)
                self._attendees[key] = attendee
            return attendee

    def set_attendance(self, event_id, attendee_id, attended, feedback, answered_at):
        with self._lock:
            key = (event_id, attendee_id)
            attendee = self._attendees.get(key)
            if attendee is None:
                return None
            attendee = replace(attendee, attended=attended, feedback=feedback, feedback_at=answered_at)
            self._attendees[key] = attendee
            return attendee

    def save_attendee(self, attendee):
        with self._lock:
            self._attendees[(attendee.event_id, attendee.id)] = attendee

    def delete_attendee(self, event_id, attendee_id):
        with self._lock:
            self._attendees.pop((event_id, attendee_id), None)

    def add_message(self, message):
        """Same contract as EventRepository.add_message."""
        with self._lock:
            if self._find(message.event_id) is None:
                return None
            chat = self._messages.setdefault(message.event_id, [])
            existing = next((m for m in chat if message.client_id and m.client_id == message.client_id), None)
            if existing is not None:
                return existing, False
            chat.append(message)
            chat.sort(key=lambda m: m.id)
        return message, True

    def list_messages(self, event_id, after_id, limit):
        with self._lock:
            chat = self._messages.get(event_id, [])
            return [m for m in chat if after_id is None or m.id > after_id][:limit]
