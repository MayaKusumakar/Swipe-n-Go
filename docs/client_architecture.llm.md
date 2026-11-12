# Client Architecture (LLM notes)

LLM keeps this updated as the design changes. Our version is in client_architecture.md.

Current state (iOS app in `ios/`, `Milestone1-v1` branch):

- **Platform:** SwiftUI, iOS 26+, Swift. Open `ios/Partner.xcodeproj`, or regenerate it from `ios/project.yml` with `xcodegen`. The app is called Swipe-n-Go on the home screen. The project and code are still named "Partner".
- **Screens (tabs):** Explore (map and list) · Discover (swipe deck) · ＋ Host (opens the Host a plan sheet) · Chats · Plans. Profile opens from the avatar at the top right of each tab. Before anything else, a sign-in screen (`Views/Onboarding/SignInView.swift`): UC Davis Google accounts only. Then onboarding covers name, pronouns, age, interests, and location and notification permissions. Profile → Account shows the signed-in email and Sign out.
- **State:** one `@Observable` store, `ios/Partner/Store/AppStore.swift`, shared through the SwiftUI environment. It saves to a JSON file on the device (`partner-state.json`).
- **Sign-in:** `Store/Auth.swift`. Google's OAuth flow for iOS (authorization code + PKCE) in the system sign-in sheet, so no SDK. It asks Google for UC Davis accounts (`hd=ucdavis.edu`) and refuses anything that isn't a verified @ucdavis.edu account; the server checks again on every request. The refresh token is kept in the Keychain and the hour-long ID token is refreshed before it expires. The client ID goes in `Info.plist` → `GoogleClientID` (empty for now, so the Google button is hidden). Dev sign-in (type a @ucdavis.edu address) appears only when the server says `dev_sign_in` is on. DEBUG launch flags: `-devSignIn you@ucdavis.edu`, `-signOut`. If the server answers 401/403, the app signs out and says why.
- **Talking to the server:** `Store/EventServer.swift` (HTTP and JSON) and `Store/AppStore+Server.swift` (syncing). Every request carries `Authorization: Bearer <token>` from `Auth`.
  - `GET /api/events?limit=50` runs every 15 seconds while the app is open, on Explore pull-to-refresh, and when the server address is saved. Server events merge into the same list as local ones.
  - Plans you host are sent with `POST /api/events`, using the app's own UUID as `id`. If the server is down, the plan stays on the phone, a banner says so, and it's retried on the next successful sync.
  - The server address is set in Profile → Server. In the simulator it defaults to `http://localhost:8080`; on a phone you type the Mac's Wi‑Fi IP. Plain `http` on the local network is allowed through `NSAllowsLocalNetworking` in `ios/Partner/Info.plist`.
  - Category mapping: the app's own category names pass straight through. The seed-data categories map as `social`→games, `music`→concert, `outdoors`→hike, `tech`→study, and anything else becomes "Day Out" (explore).
  - Hosts the app only knows by `host_name` become stand-in profiles (age hidden, rating 5.0).
  - **Joining shared events, approvals and removals go through the server** (`/api/events/<id>/attendees`, see `API.md`). The server knows who you are from your sign-in: you're the host of events your account created (also ones posted from another phone, matched by `host_id`), and your attendee entry's id is your account id (kept as `myAttendeeID`). Hosts' phones pull requests from other phones on each sync, and Accept / Decline / Remove call the server first.
  - **Private locations:** the host can turn on "Keep location private" in Host a plan (this forces approval on). The server leaves the location out of `GET /api/events` and only returns it from `GET /api/events/<id>/location` to the host or an approved attendee. Until then the app shows "Location shared once accepted", no map pin and no distance. A removed attendee loses access on the server.
- **Plans screen:** two tabs, Going and Hosting. Hosting has a smaller second row: Your plans · Saved · Drafts · Scheduled.
- **AI planner ("I'm free…", opened from the "When are you free?" bar at the top of Discover, and from the empty Discover and Plans screens):** code is in `ios/Partner/Planner/`, the screen in `Views/Planner/PlannerView.swift`.
  - `PlannerModel` runs the flow: the progress steps, a cancel when a new search starts, and the last 5 searches (stored in UserDefaults).
  - `ClaudePlanner` sends the request, the person's interests and up to 60 upcoming events to `POST /api/planner`, with times in the phone's time zone, and maps the picks back to events. Unknown ids are dropped.
  - If there's no server, or the server answers `503 ai_unavailable` or can't be reached, `OnDevicePlanner` plans on the phone instead (keyword reading, ranking, wider search when nothing fits), and the screen says why.
  - Results show "Planned by Claude" or "Planned on your iPhone", a reason per pick, and a Join or Request button on each card.
  - Unit tests: `ios/PartnerTests/PlannerTests.swift` (Swift Testing, scheme `Partner`, ⌘U).
- **Flyer reader (Host a plan → Upload flyer / Take flyer photo):** `Views/Create/FlyerScanner.swift` and `Planner/ClaudeFlyerReader.swift`.
  - Apple's on-device text recognition runs first. Then the photo is shrunk to 1568 px and re-encoded as JPEG, which drops its GPS and other metadata, and is sent with the recognized text to `POST /api/flyers/read`, where Claude reads the image.
  - The review screen shows "Read by Claude" or "Read on your iPhone", marks the fields Claude couldn't find in orange, warns if the image isn't an event flyer, and fills in the category and the duration (from the end time) too.
  - If there's no server, or it answers `503 ai_unavailable` or can't be reached, the on-device reading is used and the screen says why.
  - Unit tests: `ios/PartnerTests/FlyerReaderTests.swift`.
- **Still only on the phone (simulated):** sample events and people (can be hidden with Profile → Server → Show sample events), the simulated hosts and guests, chats, saved events, drafts, recurring events, cover photos and flyer images (only the extracted details are posted). For sample (local) events, private locations and removals are only hidden in the app, since there's no server copy.

Server side (`backend/`, mapped from the team's "Mapping these ideas to Google Cloud" table, 2026-11-11):
- **Runs locally only, and must cost $0.** No Google Cloud project or billing yet; App Engine standard later. Nothing calls a paid service unless someone turns it on on purpose.
- **Python 3.13** locally and in `app.yaml`. `app.yaml` allows one F1 instance at most (under the free 28 instance-hours a day).
- **No joins:** `attendee_count` lives on the Event and is updated in the same Datastore transaction as the Attendee (a child entity of the Event). Capacity counts the host, like the app's `spotsLeft`; full events answer `409 event_full`.
- **Nearby:** `GET /api/events/nearby` uses a stored `geohash` plus prefix range queries, then an exact distance check (`services/geo.py`). Private-location events are never returned there.
- **Recommended:** `GET /api/events/recommended` ranks by a free local similarity score (related-word groups + cosine, `services/matching.py`). Chosen over Vertex AI (no free tier) and Voyage AI (needs an account); either can replace `vectorize` later.
- **Summaries:** marked stale on create and attendance changes; `cron.yaml` calls `/tasks/summarize-stale` every 30 minutes on App Engine (by hand with curl locally). Free template text unless `AI_SUMMARIES=on` and an API key are both set.
- **Not done, on purpose:** Cloud Tasks (needs billing; cron covers it for now), users' live locations (sign-in now exists; not started), Redis, load balancing.
- **The app doesn't use the new endpoints yet** (`/nearby`, `/recommended`, `summary`, `event_full`). It still filters by distance on the phone.

Differences from our design:
- `client_architecture.md` is still blank, so there's nothing to compare against yet. The team should fill it in. The current state above can be the starting point.
- The app uses the category names listed in `API.md`, but the server's seed data uses different ones (`social`, `clubs`, ...). The team should pick one list.
- `docs/overview.md` says events show who's interested, while the Security section of `Prompt.md` says hosts only see counts. The app shows attendees today, but only from on-device sample data.
- Saved events now sit under Plans → Hosting, as requested, even though saved events are other people's plans rather than ones you host.
- Sign-in replaced the host/attendee secret tokens. Events created before that have no `host_id`, so nobody can manage them; sample data is unaffected.
- The host's name on the server now comes from their Google account, not the name typed in onboarding. The team should decide which one people see.
- Deleting your account isn't built yet. The App Store requires it for apps with sign-in.
- `docs/server_architecture.md` is still blank. The server notes above are what `backend/` follows today.
- The team's table suggested 5–6 character geohashes. At a 5-mile radius those cells are smaller than the circle and miss events near the edge, so the server picks the cell size from the radius (4 characters in Davis at 5 miles).
- The table names the child entity `Signup`; the code keeps the existing name `Attendee`.
- The AI planner uses `claude-opus-5-5`, which costs money as soon as a key is set. `claude-haiku-4-5` would cost a quarter as much; the team should decide.
