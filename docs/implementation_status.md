# Implementation Status (LLM-maintained)

> AI-maintained. Verification levels: not tested / tested locally (unit) / local server + client / deployed App Engine / blocked.

| Piece | Status | Verified |
|-------|--------|----------|
| Backend skeleton (`main.py`, Blueprints, app.yaml, .gcloudignore) | Done | Tested locally: pytest, plus gunicorn/flask + curl |
| `GET /health` | Done | Tested locally: pytest, and curl returned 200 |
| `GET /api/events` | Done, contract is still a proposal | pytest (fake repo + mocked Datastore client); curl. **Not yet run against real Datastore or the emulator.** |
| JSON 404/405/500 errors | Done | pytest + curl |
| Dev in-memory store (`EVENT_STORE=memory`) | Done | pytest + curl + emulator |
| Seed script | Written | Entity builder dry-run only. **Not run against Datastore** (blocked: no GCP project or emulator) |
| Android data layer (HttpEventsApi, parser) | Done | JVM unit tests, plus live calls against the running backend |
| Android swipe deck UI + ViewModel | Done | Unit tests, 3 Compose UI tests on the emulator, and manual checks on the emulator (below) |
| **Client <-> server on emulator** | **Done** | **Local server + client, 2026-11-04.** Medium_Phone AVD (Android 17 / API 37), backend in memory mode in WSL, `adb reverse tcp:8080 tcp:8080`. Flask logged `GET /api/events?limit=20` 200 from the app, and cards rendered. Checked by hand: drag-swipe right advances, Skip advances, tap expands the card. The error state with Retry showed when the backend was unreachable. |
| App Engine deploy | Not started | Blocked: gcloud not installed, no project |

Tests (2026-11-04):
- Backend: 24 passing (Python 3.12.3, WSL).
- Android: 21 unit tests + 3 instrumented UI tests passing. Built with Gradle 9.6.0 from a Windows-side copy, because Gradle can't build from a `\\wsl.localhost` path.

Known gotchas:
- 10.0.2.2 doesn't work on the Android 17 emulator for targetSdk 37 (local network protection). Use `adb reverse`. See decisions.md P10.
- Right after a cold boot, the first request may time out while the emulator's network comes up. Retry works.
