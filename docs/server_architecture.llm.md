# Server Architecture (LLM notes)

> AI-maintained. Our version is `server_architecture.md` (human-owned, currently blank). Human docs win if they disagree.

Current state (2026-11-04):
- Flask app on App Engine Standard, `runtime: python312`, run by gunicorn (`main:app`). Not deployed yet.
- Layout:
  - `main.py`: `create_app()` builds the app, picks the event service, registers Blueprints.
  - `api/health.py` (`health_bp`): `GET /health`
  - `api/events.py` (`events_bp`, prefix `/api/events`): validates the request, calls the service, builds the JSON response.
  - `api/errors.py`: shared JSON error format. Also handles 404/405/500 so every error is JSON.
  - `repositories/memory_event_repository.py` + `repositories/dev_sample_events.py`: DEV ONLY. With `EVENT_STORE=memory` the app serves the 8 sample events from memory, so it can be demoed without GCP. The seed script writes the same sample data to Datastore.
  - `services/event_service.py`: "upcoming" = start_time >= now (UTC). Turns Datastore, credential and config errors into `ServiceUnavailableError`.
  - `repositories/event_repository.py`: the only module that talks to Datastore. The client is created lazily so tests run without GCP.
  - `models.py`: `Event` dataclass, entity -> model -> JSON.
  - `scripts/seed_dev_events.py`: dev-only sample data (namespace `dev`, `is_seed_data=True`). Excluded from deploys.
- Data model: Datastore kind `Event`, key name = event id. Properties: title, description (unindexed), start_time, end_time, location_name, latitude, longitude, category, image_url, is_seed_data.
- The upcoming query (one inequality on start_time plus an order on the same property) uses built-in indexes, so no `index.yaml` is needed yet.
- Config comes from env vars: `GOOGLE_CLOUD_PROJECT`, `DATASTORE_NAMESPACE`, `DATASTORE_EMULATOR_HOST`, `EVENT_STORE` (dev only).

Differences from our design:
- `server_architecture.md` is blank, so there's nothing to compare against yet.
- The course's suggested layout has `users.py`, `interactions.py` and `recommendation_service.py`. These aren't created yet, deliberately, because Milestone 0 doesn't need them.
- Added `repositories/`, which isn't in the suggested layout, to keep Datastore access out of services and routes.
