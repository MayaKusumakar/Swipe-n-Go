# Decisions (LLM-maintained)

> AI-maintained log. "Approved" means a team member confirmed it. "Proposal" means it's waiting on the team.

## Approved
| # | Date | Decision |
|---|------|----------|
| 1 | 2026-11-04 | Mobile client: Kotlin + Jetpack Compose (Android). |
| 2 | 2026-11-04 | First feature (Milestone 0): the swipe deck of upcoming events. |
| 3 | 2026-11-04 | `docs/API.md` is human-only. The LLM records the implemented API in `docs/API.llm.md`. |
| 4 | 2026-11-04 | The instructor's Voluntr reference copy is removed from the project. It now lives outside the repo, at `ECS_191/Voluntr Reference`. |

## Proposals (not approved)
| # | Proposal | Notes |
|---|----------|-------|
| P1 | `GET /api/events?limit=` with the response and error shape in API.llm.md | Needs a human to write it into API.md. Already implemented, so it's easy to change. |
| P2 | App Engine runtime `python312` | Matches WSL's Python 3.12. Python 3.10 reached end of life in Oct 2026. |
| P3 | Swipes are local-only in Milestone 0 (no server call) | Recording swipes (`POST /api/interactions`) comes later. |
| P4 | Seed data goes in Datastore namespace `dev`, flagged `is_seed_data` | |
| P6 | Add a `repositories/` layer for Datastore access | |
| P7 | Dev-only in-memory event store (`EVENT_STORE=memory`) | Unblocks local demos until GCP is set up. Off by default. The real HTTP, Blueprint and service path is still used. |
| P8 | All server errors (404/405/500) use the JSON error format | |
| P10 | Local dev backend URL `http://localhost:8080` + `adb reverse` | 10.0.2.2 is blocked for targetSdk 37 on Android 17. Alternatives: request the local-network permission at runtime, or target SDK 36. |
| P9 | Android package `com.swipengo.app`, minSdk 26 | minSdk 26 gives `java.time` without desugaring (about 97% of devices). |

## Still open
- GCP project: owner, project ID, Datastore Mode enabled, who installs gcloud.
- Local dev database: Datastore emulator or a shared dev project.
- Whether the deployed app reads the `dev` namespace for the demo (see the comment in app.yaml).
- Narrowing to one event type (instructor feedback).
- Branch workflow into `main`.
