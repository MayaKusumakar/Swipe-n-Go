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
