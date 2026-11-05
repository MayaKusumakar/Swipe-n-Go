# CLAUDE.md

Rules for Claude / any LLM working in this repo.

Human only files. Do not create, edit, rewrite, or delete these. You can read them.
- docs/overview.md
- docs/client_architecture.md
- docs/server_architecture.md
- docs/API.md
- anything in docs/features/

If you think one of these needs to change, tell us what and why and we will edit it ourselves. Don't fix spelling or grammar in them either.

Files the LLM is allowed to edit (mark them as LLM-maintained; our docs win if they disagree):
- docs/client_architecture.llm.md - keep notes here on how the design is changing as we build
- docs/server_architecture.llm.md - same, for the server
- docs/API.llm.md - what the server code actually does; proposed API changes go here for us to copy into API.md
- docs/decisions.md - decisions we made + open proposals (don't mark a proposal approved until one of us says so)
- docs/implementation_status.md - what's built and how it was verified

If the code ends up different from what's in our docs, write it down in the matching .llm.md file and let us know.

Backend rules (from the course, not optional):
- Google App Engine Standard only (not Flexible, not another host). Python 3.10-3.13.
- Flask, with routes split into Blueprints in backend/api/. Logic in backend/services/, Datastore access in backend/repositories/, models in backend/models.py. No single giant app file.
- Firestore in Datastore Mode with google-cloud-datastore (not Firestore Native, not the firestore client).
- Keep backend/app.yaml and backend/.gcloudignore.

Client: Kotlin + Jetpack Compose (Android).

Git and secrets:
- Don't commit, push, merge, or rewrite git history unless we ask.
- Never put API keys/credentials in code or commit them. Secrets stay server-side in env vars; only placeholder names go in .env.example.

Commands (run from WSL, inside backend/):
- setup server: python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
- run server: .venv/bin/flask --app main run --host 0.0.0.0 --port 8080   (prefix EVENT_STORE=memory to use dev sample data without Datastore)
- run tests: .venv/bin/python -m pytest

Client commands (from android/; Gradle can't build from a \\wsl.localhost path, so on this machine build a Windows-side copy):
- first: adb reverse tcp:8080 tcp:8080   (once per emulator boot; 10.0.2.2 is blocked on Android 17 for targetSdk 37)
- build + install: ./gradlew installDebug   (backend URL: -PswipeNGo.apiBaseUrl=..., default http://localhost:8080)
- unit tests: ./gradlew testDebugUnitTest
- UI tests (emulator running): ./gradlew connectedDebugAndroidTest
