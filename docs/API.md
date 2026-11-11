# API

Matches the server code in `backend/` on the `Anant` branch (`backend/api/`).

Base URL:
- Local, in the iOS simulator: `http://localhost:8080`
- Local, on a real iPhone on the same Wi‑Fi: `http://<your Mac's IP>:8080`
- Android emulator: `http://10.0.2.2:8080`
- App Engine: not deployed yet

Run locally with built-in sample events and no Google Cloud setup (events posted while it runs are kept in memory and lost on restart):

```
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
EVENT_STORE=memory flask --app main run --host 0.0.0.0 --port 8080
python -m pytest        # run the tests
```

Every error, including unknown routes (`404 not_found`), wrong methods (`405 method_not_allowed`) and crashes (`500 internal_error`), uses this format:

```json
{ "error": { "code": "string", "message": "string" } }
```

No endpoint checks sign-in yet.

---

## The Event object

| Field | Type | Notes |
|---|---|---|
| `id` | string | UUID for new events. Seed data uses ids like `seed-001`. |
| `title` | string | 1–120 characters |
| `description` | string | up to 2000 characters, may be `""` |
| `start_time` | string | ISO‑8601 with UTC offset, e.g. `2026-11-06T19:00:00+00:00` |
| `end_time` | string \| null | after `start_time` |
| `location_name` | string | e.g. `"Memorial Union"` |
| `latitude`, `longitude` | number \| null | sent together or not at all |
| `category` | string | lowercase word. The iOS app uses `run, gym, hike, cycling, sports, yoga, food, coffee, drinks, concert, movies, art, study, games, explore`. Seed data also uses `social, clubs, music, outdoors, tech`. |
| `image_url` | string \| null | always null for now (no uploads yet) |
| `host_name` | string \| null | display name of whoever posted it |
| `address` | string \| null | |
| `capacity` | integer \| null | 2–500 |
| `attendee_count` | integer | always 0 for now (no RSVP endpoint yet) |
| `cost` | string \| null | free text, e.g. `"Free"`, `"$15 cover"` |
| `tags` | string[] | up to 10, each up to 30 characters |
| `level` | string \| null | `anyone`, `beginner`, `intermediate` or `advanced` |
| `requires_approval` | boolean | default `false` |

Events stored before the optional fields existed return them as `null` / `0` / `[]` / `false`.

---

## GET /health

Checks that the server is up. Doesn't touch the database.

Response `200`:
```json
{ "status": "ok" }
```

## GET /api/events

Upcoming events (`start_time` ≥ now, UTC), soonest first. Used by the swipe deck and map.

Query params:
- `limit`: optional integer 1–50, default 20

Response `200`:
```json
{ "events": [ /* Event objects */ ], "count": 1 }
```
No events: `200 {"events": [], "count": 0}`.

Errors:
- `400 invalid_parameter`: `limit` is not an integer from 1 to 50
- `503 datastore_unavailable`: Datastore unreachable or not configured

Code: `backend/api/events.py` → `services/event_service.py` → `repositories/`.

## POST /api/events

Creates an event. Used by the iOS app's "Host a plan" screen.

Request body (JSON). Required: `title`, `start_time`, `location_name`, `category`. Everything else in the Event table is optional, except `attendee_count` and `image_url`, which are ignored.
```json
{
  "id": "6f1c2a3e-1b2c-4d5e-8f90-123456789abc",
  "title": "Sunrise Arboretum 5K",
  "description": "Easy pace, coffee after.",
  "start_time": "2026-11-06T14:30:00+00:00",
  "end_time": "2026-11-06T15:15:00+00:00",
  "location_name": "UC Davis Arboretum",
  "latitude": 38.5372,
  "longitude": -121.7531,
  "category": "run",
  "host_name": "Anant Katiyar",
  "address": "Garrod Dr, Davis, CA",
  "capacity": 6,
  "cost": "Free",
  "tags": ["Running"],
  "level": "beginner",
  "requires_approval": false
}
```
- `id` is optional. If sent, it must be a UUID, and the event keeps that id. The iOS app sends its own id, so retrying a post never creates a duplicate. Without it, the server makes a UUID.
- `start_time` must be in the future and include a UTC offset.
- Text fields are trimmed.

Response `201`: the created Event object.

Errors:
- `400 invalid_event`: the message names the bad field, e.g. `"capacity must be an integer from 2 to 500"`
- `409 event_exists`: an event with that `id` already exists
- `503 datastore_unavailable`

Code: `backend/api/events.py` (route), `backend/api/event_input.py` (validation), `services/event_service.py`, `repositories/`.

## POST /api/planner

The AI planner behind the app's "I'm free…" screen. The app sends what the student typed, their interests, and the events it can see. Claude (`claude-opus-5-5`, low effort, structured output) reads them and returns picks with a reason for each. The Claude API key stays on the server (`ANTHROPIC_API_KEY`: in `backend/.env` locally, Secret Manager in production). Nothing is stored.

Request body (JSON):
```json
{
  "query": "free tomorrow after 5, want something active, I don't know anyone",
  "now": "2026-11-11T12:00:00-08:00",
  "interests": ["run", "food"],
  "events": [
    {
      "id": "6f1c2a3e-1b2c-4d5e-8f90-123456789abc",
      "title": "Pickup basketball 3v3",
      "category": "sports",
      "start_time": "2026-11-12T18:00:00-08:00",
      "duration_minutes": 90,
      "location_name": "ARC Courts",
      "distance_miles": 1.1,
      "cost": "Free",
      "level": "intermediate",
      "attendee_count": 3,
      "spots_left": 3,
      "requires_approval": false,
      "tags": ["Casual"]
    }
  ]
}
```
- `query`: 1–300 characters.
- `now`: the student's current time with their UTC offset. It sets their time zone: Claude reads "tonight" and writes times in that zone.
- `interests`: up to 15 strings.
- `events`: up to 80 events with unique ids. `distance_miles`, `cost`, `level`, `attendee_count`, `spots_left`, `requires_approval` and `tags` are optional.

Response `200`:
```json
{
  "understood": "Tomorrow after 5 PM · something active · meet people",
  "window_start": "2026-11-12T17:00:00-08:00",
  "window_end": "2026-11-13T00:00:00-08:00",
  "picks": [
    { "event_id": "6f1c2a3e-1b2c-4d5e-8f90-123456789abc", "reason": "3 people already going, 6 PM at the ARC, a mile away." }
  ],
  "note": "",
  "model": "claude-opus-5-5"
}
```
- `picks`: at most 5, best fit first. Every `event_id` is one of the ids that were sent. The server drops unknown or repeated ids.
- `window_start` / `window_end` may be `null`.
- `note` is `""` unless nothing fit exactly and the search was widened.
- With no events, Claude isn't called: `picks` is `[]` and `note` says why.

Errors:
- `400 invalid_planner_request`: the message names the bad field.
- `503 ai_unavailable`: no API key on the server, key rejected, rate limited, Claude unreachable, or the request was declined. The message is shown to the user, and the app falls back to its on-device planner.

Code: `backend/api/planner.py` (route), `backend/api/planner_input.py` (validation), `backend/services/planner_service.py` (prompt, Claude call, output checks).

---

Not built yet: sign-in (@ucdavis.edu Google accounts), editing and deleting events, RSVP / saved events on the server, image uploads, filters (category, distance, date), pagination, rate limiting.
