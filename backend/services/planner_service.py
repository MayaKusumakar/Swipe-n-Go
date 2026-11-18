"""AI planner: turns "I'm free tomorrow after 5, want something active" into picks.

The app sends the request text, the student's interests and the events it can
see; Claude reads them and returns structured JSON (what it understood, the
time window, and up to five picks with a reason each). The API key never leaves
the server: it's read from ANTHROPIC_API_KEY (backend/.env locally, Secret
Manager in production).
"""
import json
from dataclasses import dataclass
from datetime import datetime

from pydantic import BaseModel, Field

from services import claude_call
from services.claude_call import MODEL, AIUnavailableError, clip

MAX_PICKS = 5
MAX_REASON_LENGTH = 160
MAX_UNDERSTOOD_LENGTH = 90

# The planner's name for "Claude can't answer right now" (see services/claude_call.py).
PlannerUnavailableError = AIUnavailableError


@dataclass(frozen=True)
class CandidateEvent:
    """An event the app can show; already validated by api/planner_input.py."""
    id: str
    title: str
    category: str
    start_time: datetime
    duration_minutes: int
    location_name: str
    distance_miles: float | None
    cost: str
    level: str
    attendee_count: int
    spots_left: int
    requires_approval: bool
    tags: tuple[str, ...]


@dataclass(frozen=True)
class Pick:
    event_id: str
    reason: str


@dataclass(frozen=True)
class Plan:
    understood: str
    window_start: datetime | None
    window_end: datetime | None
    picks: list[Pick]
    note: str
    model: str

    def to_dict(self):
        return {
            "understood": self.understood,
            "window_start": self.window_start.isoformat() if self.window_start else None,
            "window_end": self.window_end.isoformat() if self.window_end else None,
            "picks": [{"event_id": p.event_id, "reason": p.reason} for p in self.picks],
            "note": self.note,
            "model": self.model,
        }


# What Claude must return. Structured outputs guarantee this shape.
class _PickOutput(BaseModel):
    event_id: str = Field(description="The id of an event from the list, copied exactly.")
    reason: str = Field(description="Why it fits this student, at most 18 words.")


class _PlanOutput(BaseModel):
    understood: str = Field(description="What they asked for in at most 10 words, parts joined with ' · '.")
    window_start: str = Field(description="Start of their free time, ISO-8601 with the UTC offset given in 'now'.")
    window_end: str = Field(description="End of their free time, ISO-8601 with the same offset.")
    picks: list[_PickOutput] = Field(description="Up to 5 events, best fit first. Empty if nothing in the list is upcoming.")
    note: str = Field(description="Empty, or one short sentence if nothing fit exactly and you widened the search.")


SYSTEM_PROMPT = """\
You are the planner inside Swipe-n-Go, a UC Davis app that helps students find things to do \
and people to do them with. A student tells you when they're free and what they feel like doing; \
you pick the events from the provided list that fit best.

How to read the request:
- "I'm free" means available, not "costs nothing". Only treat cost as a preference when they \
say things like cheap, broke, budget, or for free.
- "Active" means anything that gets them moving (running, gym, hiking, cycling, sports, yoga).
- If they say they don't know anyone, are going alone, or want to meet people, favour events \
with people already going and no host approval step.
- If they're new, a beginner, or nervous, favour events marked anyone or beginner.
- If no day is given, assume the next occurrence of the time they gave; if no time is given, \
use the rest of that day; if nothing is given, use the next seven days.

How to pick:
- Only choose events from the list, and copy each event_id exactly. Never invent events or details.
- Prefer events that start inside their free time, match what they asked for, and match their \
interests, in that order. Closer and sooner break ties.
- If nothing fits exactly, pick the closest options and say what you changed in `note`.
- Each reason speaks to the student as "you", names one or two concrete details from the event \
(time, distance, people going, level, cost, a shared interest), and has no emojis.
- Some events keep their place private until the host accepts you: their place says so and \
they have no distance. Never guess or mention where those are.
- All times are in the student's local time zone (the offset in `now`). Write times the way \
they'd say them, like "6 PM", never as raw ISO timestamps.
"""


class PlannerService:
    def __init__(self, client=None, model=MODEL):
        self._client = client
        self._model = model

    @property
    def client(self):
        # Created on first use so the server starts without an API key.
        if self._client is None:
            self._client = claude_call.make_client()
        return self._client

    def plan(self, query, now, interests, events):
        if not events:
            return Plan(understood="", window_start=None, window_end=None, picks=[],
                        note="There are no upcoming events to choose from yet.", model=self._model)

        context = {
            "now": now.isoformat(),
            "weekday": now.strftime("%A"),
            "interests": interests,
            "events": [_describe(e, now.tzinfo) for e in events],
        }
        output = claude_call.parse(
            self.client,
            model=self._model,
            system=SYSTEM_PROMPT,
            content=f"Context:\n{json.dumps(context, ensure_ascii=False)}\n\nStudent's request: {query}",
            output_format=_PlanOutput,
        )
        return self._clean(output, events)

    def _clean(self, output, events):
        """Trust nothing blindly: keep only real, unique event ids and short text."""
        known = {e.id for e in events}
        picks, seen = [], set()
        for pick in output.picks:
            if pick.event_id in known and pick.event_id not in seen:
                seen.add(pick.event_id)
                picks.append(Pick(event_id=pick.event_id, reason=clip(pick.reason, MAX_REASON_LENGTH)))
            if len(picks) == MAX_PICKS:
                break
        return Plan(
            understood=clip(output.understood, MAX_UNDERSTOOD_LENGTH),
            window_start=_parse_time(output.window_start),
            window_end=_parse_time(output.window_end),
            picks=picks,
            note=clip(output.note, MAX_REASON_LENGTH),
            model=self._model,
        )


def _describe(e, tz):
    return {
        "event_id": e.id,
        "title": e.title,
        "category": e.category,
        # In the student's time zone, so reasons quote the times they see in the app.
        "starts": e.start_time.astimezone(tz).isoformat(),
        "minutes": e.duration_minutes,
        "place": e.location_name,
        "miles_away": e.distance_miles,
        "cost": e.cost,
        "level": e.level,
        "people_going": e.attendee_count,
        "spots_left": e.spots_left,
        "host_approves_requests": e.requires_approval,
        "tags": list(e.tags),
    }



def _parse_time(value):
    try:
        parsed = datetime.fromisoformat((value or "").replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else None
