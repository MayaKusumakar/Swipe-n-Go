"""Per-user request limits, so one account can't run up costs or flood the app.

Counts live in this instance's memory: free (no Datastore reads or writes) and,
with app.yaml's max_instances: 1, they cover the whole app. A restart or deploy
resets them. Windows are fixed: each minute, hour, or UTC day starts fresh.
"""
import math
import threading
import time
from dataclasses import dataclass

MINUTE, HOUR, DAY = 60, 3600, 86400

# Above this many counters, expired ones are dropped.
_MAX_COUNTERS = 10_000


@dataclass(frozen=True)
class Limit:
    name: str
    max_requests: int
    window: int          # seconds
    message: str
    method: str | None = None   # None: every method
    route: str | None = None    # Flask route pattern; None: every /api route

    def applies_to(self, method, route):
        return (self.method is None or self.method == method) and (self.route is None or self.route == route)


DEFAULT_LIMITS = (
    Limit("requests", 120, MINUTE, "You're making requests too quickly."),
    Limit("new_events", 20, DAY, "You've created the most events allowed today (20).",
          method="POST", route="/api/events"),
    Limit("join_requests", 60, HOUR, "You've sent too many join requests this hour.",
          method="POST", route="/api/events/<event_id>/attendees"),
    # The planner calls the Claude API, which costs money per request.
    Limit("planner", 5, MINUTE, "The planner is busy for you right now.",
          method="POST", route="/api/planner"),
    Limit("planner_daily", 20, DAY, "You've used the planner the most times allowed today (20).",
          method="POST", route="/api/planner"),
    # Reading a flyer also calls Claude.
    Limit("flyer_reads", 5, MINUTE, "You're reading flyers too quickly.",
          method="POST", route="/api/flyers/read"),
    Limit("flyer_reads_daily", 20, DAY, "You've read the most flyers allowed today (20).",
          method="POST", route="/api/flyers/read"),
    # "Describe your plan" calls Claude too (experimental, on when EXPERIMENTS=event_parse).
    # experimental/routes.py already allows 10 a minute; this adds the daily cap.
    Limit("event_parse_daily", 20, DAY, "You've filled in the most plans from a description allowed today (20).",
          method="POST", route="/api/experimental/events/parse"),
    # Chat messages are Datastore writes; generous for real conversation, not for flooding.
    Limit("messages", 30, MINUTE, "You're sending messages too quickly.",
          method="POST", route="/api/events/<event_id>/messages"),
    Limit("messages_daily", 1000, DAY, "You've sent the most messages allowed today (1000).",
          method="POST", route="/api/events/<event_id>/messages"),
    # Covers are the biggest Datastore writes.
    Limit("cover_uploads", 30, HOUR, "You've uploaded too many covers this hour.",
          method="PUT", route="/api/events/<event_id>/cover"),
)


class RateLimiter:
    def __init__(self, limits=DEFAULT_LIMITS, clock=time.time):
        self._limits = limits
        self._clock = clock
        self._counts = {}    # (user id, limit name) -> (window end, count)
        self._lock = threading.Lock()

    def check(self, user_id, method, route):
        """Counts one request. Returns None if it's allowed, otherwise
        (the Limit it hit, seconds until that limit resets). Refused requests aren't counted."""
        now = self._clock()
        with self._lock:
            counted = []
            for limit in self._limits:
                if not limit.applies_to(method, route):
                    continue
                key = (user_id, limit.name)
                window_end = now - now % limit.window + limit.window
                saved_end, count = self._counts.get(key, (window_end, 0))
                if saved_end != window_end:
                    count = 0
                if count >= limit.max_requests:
                    return limit, max(1, math.ceil(window_end - now))
                counted.append((key, window_end, count + 1))
            for key, window_end, count in counted:
                self._counts[key] = (window_end, count)
            if len(self._counts) > _MAX_COUNTERS:
                self._counts = {key: value for key, value in self._counts.items() if value[0] > now}
        return None
