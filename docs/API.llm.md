# API (LLM-maintained)

> AI-maintained. Describes what the server code currently does. `API.md` is the human-owned spec and wins if they disagree.
> Status of `GET /api/events`: **PROPOSAL, not yet in API.md.** The team needs to approve it (or change it) and write it into API.md.

Base URL: local `http://localhost:8080` (Android emulator: `http://10.0.2.2:8080`). App Engine URL TBD.

Error format (all endpoints, including unknown routes `404 not_found`, wrong methods `405 method_not_allowed`, and crashes `500 internal_error`):
```json
{ "error": { "code": "string", "message": "string" } }
```

## GET /health
Matches API.md. Returns `200 {"status": "ok"}`. Doesn't touch the database.

## GET /api/events  (proposal)
Upcoming events (start_time >= now, UTC), soonest first. Used by the swipe deck.

Query params:
- `limit` (optional, integer 1-50, default 20)

`200`:
```json
{
  "events": [
    {
      "id": "seed-001",
      "title": "Trivia Night",
      "description": "Teams of up to 6.",
      "start_time": "2026-11-06T19:00:00+00:00",
      "end_time": "2026-11-06T21:00:00+00:00",
      "location_name": "Memorial Union",
      "latitude": 38.5424,
      "longitude": -121.7494,
      "category": "social",
      "image_url": null
    }
  ],
  "count": 1
}
```
- Times are ISO-8601 with UTC offset. `end_time`, `latitude`, `longitude`, `image_url` may be null.
- No events: `200 {"events": [], "count": 0}`.

Errors:
- `400 invalid_parameter`: `limit` not an integer from 1 to 50.
- `503 datastore_unavailable`: Datastore unreachable or not configured.

Code: `backend/api/events.py` -> `services/event_service.py` -> `repositories/event_repository.py`.

Not covered yet: auth or a user id, pagination cursors, filters (category, distance, date), recording swipes.
