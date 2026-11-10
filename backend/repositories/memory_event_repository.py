"""DEVELOPMENT ONLY: event store held in memory (EVENT_STORE=memory).

Lets the app be demoed locally before a GCP project or Datastore emulator is
set up. Same interface as EventRepository. Events added while the server runs
are lost when it stops.
"""
import threading


class InMemoryEventRepository:
    def __init__(self, events):
        self._events = sorted(events, key=lambda event: event.start_time)
        self._lock = threading.Lock()
        self._attendees = {}  # (event_id, attendee_id) -> Attendee

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

    def list_attendees(self, event_id):
        with self._lock:
            attendees = [a for (eid, _), a in self._attendees.items() if eid == event_id]
        return sorted(attendees, key=lambda a: a.created_at)

    def get_attendee(self, event_id, attendee_id):
        with self._lock:
            return self._attendees.get((event_id, attendee_id))

    def save_attendee(self, attendee):
        with self._lock:
            self._attendees[(attendee.event_id, attendee.id)] = attendee

    def delete_attendee(self, event_id, attendee_id):
        with self._lock:
            self._attendees.pop((event_id, attendee_id), None)
