"""Small fixed-window rate limiter, kept in memory on each instance.

Good enough to stop one runaway client from running up the Claude bill.
app.yaml allows a single F1 instance, so per-instance is effectively global
today; with more instances the real ceiling is (instances x limit). Move the
counts to Datastore if that ever matters.
"""
import threading
import time

MAX_KEYS = 10_000


class RateLimiter:
    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._lock = threading.Lock()
        self._windows = {}  # key -> (window_start, count)

    def allow(self, key, limit, window_seconds=60):
        """True if this request fits under `limit` per window; counts it if so."""
        if limit <= 0:
            return True
        now = self._clock()
        start = now - now % window_seconds
        with self._lock:
            if len(self._windows) > MAX_KEYS:
                self._windows.clear()
            window_start, count = self._windows.get(key, (start, 0))
            if window_start != start:
                window_start, count = start, 0
            if count >= limit:
                return False
            self._windows[key] = (window_start, count + 1)
            return True
