"""DEVELOPMENT ONLY: event store held in memory (EVENT_STORE=memory).

Lets the app be demoed locally before a GCP project or Datastore emulator is
set up. Same interface as EventRepository.
"""


class InMemoryEventRepository:
    def __init__(self, events):
        self._events = sorted(events, key=lambda event: event.start_time)

    def list_upcoming(self, now, limit):
        return [event for event in self._events if event.start_time >= now][:limit]
