# API

Matches the server code in `backend/` on the `Milestone1-v1` branch (`backend/api/`).

Base URL:
- Local, in the iOS simulator: `http://localhost:8080`
- Local, on a real iPhone on the same Wi‑Fi: `http://<your Mac's IP>:8080`
- Android emulator: `http://10.0.2.2:8080`
- App Engine: not deployed yet

Run locally with built-in sample events and no Google Cloud setup (events posted while it runs are kept in memory and lost on restart):

```
cd backend
python3.13 -m venv .venv && source .venv/bin/activate   # same Python as App Engine (app.yaml)
pip install -r requirements-dev.txt
EVENT_STORE=memory flask --app main run --host 0.0.0.0 --port 8080
python -m pytest        # run the tests
```

Every error, including unknown routes (`404 not_found`), wrong methods (`405 method_not_allowed`) and crashes (`500 internal_error`), uses this format:

```json
{ "error": { "code": "string", "message": "string" } }
```

**Every `/api/*` endpoint needs sign-in** (except `GET /api/auth/config`): send `Authorization: Bearer <token>`, where the token is the Google ID token of a verified **@ucdavis.edu** account. See **Sign-in** below. Without a valid token: `401 unauthenticated`. A real Google account that isn't a verified @ucdavis.edu one: `403 ucdavis_only`. `/health` and `/tasks/*` aren't under `/api` and don't use it.

Try it locally with dev sign-in (no Google setup): start the server with `DEV_SIGN_IN=on` and send `Authorization: Bearer dev:you@ucdavis.edu:Your Name`, e.g.
```
curl -H "Authorization: Bearer dev:maya@ucdavis.edu:Maya" localhost:8080/api/events
```

---

## Sign-in

Only verified **@ucdavis.edu** Google accounts can use Swipe-n-Go. Free: Google Sign-In costs nothing, and the server checks tokens itself (no Datastore read, no paid API).

How the server checks a token (`backend/services/auth_service.py`), on every request:
- The signature, against Google's public keys (fetched from Google at most once an hour and cached; refetched early only if Google starts using a new key).
- `aud` is one of our OAuth client IDs (`GOOGLE_CLIENT_IDS`, comma-separated), `iss` is Google, and the token hasn't expired.
- `email_verified` is true, `hd` (the Google Workspace domain) is `ucdavis.edu`, and the email ends in exactly `@ucdavis.edu` (so not `@health.ucdavis.edu`, not personal Gmail).

The account id is Google's `sub`. Events store it as `host_id`, and an attendee's `id` is their account id.

**Dev sign-in** (local testing only): with `DEV_SIGN_IN=on`, the server also accepts `dev:<email>:<name>` tokens. The email must still be @ucdavis.edu, and the account id is `dev-<email>`. It is always off on App Engine (`GAE_ENV` set), whatever the setting.

Setup (one person, free, no billing): Google Cloud Console → APIs & Services → OAuth consent screen, then Credentials → Create OAuth client ID → iOS, with bundle ID `com.anantkatiyar.Partner`. Put the client ID in `ios/Partner/Info.plist` (`GoogleClientID`) and in the server's `GOOGLE_CLIENT_IDS`.

### GET /api/auth/config

No sign-in needed. `{"allowed_domain": "ucdavis.edu", "dev_sign_in": false}`. The app uses it to decide whether to show dev sign-in.

### POST /api/auth/sign-in

Called by the app once after signing in. Saves the account (a `User` entity, one write per sign-in) and returns it: `{"id": "1093…", "email": "maya@ucdavis.edu", "name": "Maya Lee", "picture_url": "https://…"}`. Errors: `401`, `403 ucdavis_only`.

### GET /api/auth/me

The signed-in account, same shape. No Datastore read.

Code: `backend/api/auth.py` (routes and the check before every request), `backend/services/auth_service.py`, `backend/repositories/user_repository.py`.

---

## The Event object

| Field | Type | Notes |
|---|---|---|
| `id` | string | UUID for new events. Seed data uses ids like `seed-001`. |
| `title` | string | 1–120 characters |
| `description` | string | up to 2000 characters, may be `""` |
| `start_time` | string | ISO‑8601 with UTC offset, e.g. `2026-11-06T19:00:00+00:00` |
| `end_time` | string \| null | after `start_time` |
| `location_name` | string \| null | e.g. `"Memorial Union"`. `null` in `GET /api/events` when `location_private` is true |
| `latitude`, `longitude` | number \| null | sent together or not at all. `null` in the list for private locations |
| `category` | string | lowercase word. The iOS app uses `run, gym, hike, cycling, sports, yoga, food, coffee, drinks, concert, movies, art, study, games, explore`. Seed data also uses `social, clubs, music, outdoors, tech`. |
| `image_url` | string \| null | always null for now (no uploads yet) |
| `host_id` | string \| null | account id of the host (see **Sign-in**). `null` for sample data |
| `host_name` | string \| null | the host's name from their account. Any `host_name` sent when creating is ignored |
| `address` | string \| null | `null` in the list for private locations |
| `capacity` | integer \| null | 2–500 |
| `attendee_count` | integer | approved attendees, not counting the host. Kept on the event (Datastore has no joins) and updated together with the attendee in one transaction |
| `cost` | string \| null | free text, e.g. `"Free"`, `"$15 cover"` |
| `tags` | string[] | up to 10, each up to 30 characters |
| `level` | string \| null | `anyone`, `beginner`, `intermediate` or `advanced` |
| `requires_approval` | boolean | default `false`. Always `true` when `location_private` is true |
| `location_private` | boolean | default `false`. The location is shared only with the host and approved attendees, through `GET /api/events/<id>/location` |
| `summary` | string \| null | short "what it is / who's going" blurb written by the summaries job (see **Summaries**). `null` until the job has run. Never mentions the location |

`capacity` counts the host, like the app's "spots left": an event is full when `attendee_count` reaches `capacity - 1`.

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

## GET /api/events/nearby

Upcoming events within a radius, soonest first. For the map and "near me".

Query params:
- `lat`, `lng`: required, the searcher's position
- `radius_miles`: optional, 0.1–25, default 5
- `limit`: optional integer 1–50, default 20

Response `200`: `{"events": [ /* Event objects, each plus "distance_miles" */ ], "count": 2}`.

Events with a private location are **never** returned here, so their position can't be narrowed down by searching from different spots. They still appear in `GET /api/events` with the location hidden. Events without coordinates are left out too.

How it works (Datastore has no geo queries): each event stores a `geohash` of its coordinates. The server picks the geohash cell size that is at least as big as the radius, runs one prefix range query for the cell around the searcher and each of its 8 neighbours (at most 9 queries), then keeps events within the exact distance. No custom Datastore index is needed.

Errors:
- `400 invalid_parameter`: missing or out-of-range `lat`, `lng`, `radius_miles` or `limit`
- `503 datastore_unavailable`

Code: `backend/api/events.py` → `services/event_service.py` (`nearby_events`) → `services/geo.py`.

## GET /api/events/recommended

Events that match the student's interests, best match first. Free: no AI or embedding API is called.

Query params:
- `interests`: required, 1–15 comma-separated words or phrases, each up to 30 characters, e.g. `hiking,coffee`
- `lat`, `lng`, `radius_miles`: optional. With them, candidates are the nearby events (same rules as `/nearby`, so no private locations); without them, the next 50 upcoming events.
- `limit`: optional integer 1–50, default 20

Response `200`: `{"events": [ /* Event objects, each plus "match_score" (0–1) and "distance_miles" (null without a location) */ ], "count": 1}`. Events that don't match at all are left out.

Matching: each text becomes a small vector of related-word groups (e.g. hiking, backpacking, trail, walk and nature are one group) plus its own words, and events are ranked by cosine similarity to the interests. So "hiking, backpacking" matches "Arboretum Sunset Walk". Replace `vectorize` in `services/matching.py` to use real embeddings later.

Errors: `400 invalid_parameter`, `503 datastore_unavailable`.

Code: `backend/api/events.py` → `services/event_service.py` (`recommended_events`) → `services/matching.py`.

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

- `location_private` is optional (`true`/`false`). When `true`, the server also sets `requires_approval` to `true`.

Response `201`: the created Event object with its full location. The signed-in user is the host (`host_id`), and `host_name` comes from their account.

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

## Summaries (internal)

`GET` or `POST /tasks/summarize-stale` rewrites up to 20 stale event summaries and answers `{"summarized": 3}`. Not for the app.

- An event is marked stale when it's created and whenever its `attendee_count` changes. The summary is never written inline.
- On App Engine, `cron.yaml` calls it every 30 minutes. Only App Engine cron (`X-Appengine-Cron`) or Cloud Tasks (`X-AppEngine-QueueName`) may call it there; App Engine strips those headers from outside requests. Anyone else gets `403 forbidden`.
- Locally (no `GAE_ENV`), it can be called from the same machine only: `curl localhost:8080/tasks/summarize-stale`.
- **Free by default:** summaries are built from the event's own fields. Claude writes them only when `AI_SUMMARIES=on` **and** `ANTHROPIC_API_KEY` are both set, which costs money per summary. Any Claude failure falls back to the free version.

Code: `backend/api/tasks.py`, `backend/services/summary_service.py`, `backend/cron.yaml`.

---

## Attendees and private locations

Who you are comes from your sign-in. The host is the account that created the event; an attendee entry belongs to the account it's for. Not allowed: `403 forbidden`. An unknown event or attendee: `404 not_found`. These checks run on the server; the app hiding a button is not the protection.

The Attendee object:

| Field | Type | Notes |
|---|---|---|
| `id` | string | the attendee's account id (one entry per person per event) |
| `name` | string | from their account |
| `status` | string | `pending` or `approved` |

### POST /api/events/\<id\>/attendees

Ask to join, as the signed-in user. No body.

Response `201`: the Attendee. Status is `approved` straight away unless the event has `requires_approval`, in which case it is `pending`. Asking again returns your existing entry with `200`.

Errors: `403 forbidden` (you're the host), `404 not_found`, `409 event_full` (only for events without approval; a request to an approval event is always accepted as `pending`).

### GET /api/events/\<id\>/attendees/me

Your own entry for this event, e.g. to see when the host approved you. `404 not_found` if you haven't asked to join.

### GET /api/events/\<id\>/attendees

Host only. Response `200`: `{"attendees": [ /* Attendee objects, oldest first */ ]}`.

### POST /api/events/\<id\>/attendees/\<attendee_id\>/approve

Host only. Accepts a pending request. Response `200`: the updated Attendee. Approving someone already approved changes nothing.

Errors: `409 event_full` (the request stays `pending`).

### DELETE /api/events/\<id\>/attendees/\<attendee_id\>

Removes an attendee, or declines a request. Allowed for the host, or for that attendee themselves (leaving). Response `204`, no body. A removed attendee can no longer get a private location. Removing an approved attendee lowers `attendee_count`; declining a pending request doesn't change it.

### GET /api/events/\<id\>/location

The full location: `{"location_name", "address", "latitude", "longitude"}`. Open to anyone for events without a private location. For private ones, only the host or an **approved** attendee gets `200`; everyone else gets `403 forbidden`.

Code: `backend/api/events.py` (routes), `services/event_service.py` (all permission checks), `repositories/` (attendees are stored as child entities of their event).

---

Not built yet: deleting your account (the App Store requires it), editing and deleting events, users' live locations, chats and saved events on the server, image uploads, category and date filters, pagination, rate limiting, Cloud Tasks (cron only for now).
