# Client Architecture (LLM notes)

LLM keeps this updated as the design changes. Our version is in client_architecture.md.

Current state (iOS app in `ios/`, `Anant` branch):

- **Platform:** SwiftUI, iOS 26+, Swift. Open `ios/Partner.xcodeproj`, or regenerate it from `ios/project.yml` with `xcodegen`. The app is called Swipe-n-Go on the home screen. The project and code are still named "Partner".
- **Screens (tabs):** Explore (map and list) · Discover (swipe deck) · ＋ Host (opens the Host a plan sheet) · Chats · Plans. Profile opens from the avatar at the top right of each tab. Onboarding covers name, pronouns, age, interests, and location and notification permissions.
- **State:** one `@Observable` store, `ios/Partner/Store/AppStore.swift`, shared through the SwiftUI environment. It saves to a JSON file on the device (`partner-state.json`).
- **Talking to the server:** `Store/EventServer.swift` (HTTP and JSON) and `Store/AppStore+Server.swift` (syncing).
  - `GET /api/events?limit=50` runs every 15 seconds while the app is open, on Explore pull-to-refresh, and when the server address is saved. Server events merge into the same list as local ones.
  - Plans you host are sent with `POST /api/events`, using the app's own UUID as `id`. If the server is down, the plan stays on the phone, a banner says so, and it's retried on the next successful sync.
  - The server address is set in Profile → Server. In the simulator it defaults to `http://localhost:8080`; on a phone you type the Mac's Wi‑Fi IP. Plain `http` on the local network is allowed through `NSAllowsLocalNetworking` in `ios/Partner/Info.plist`.
  - Category mapping: the app's own category names pass straight through. The seed-data categories map as `social`→games, `music`→concert, `outdoors`→hike, `tech`→study, and anything else becomes "Day Out" (explore).
  - Hosts the app only knows by `host_name` become stand-in profiles (age hidden, rating 5.0).
- **AI planner ("I'm free…", opened from the first chip on Discover):** code is in `ios/Partner/Planner/`, the screen in `Views/Planner/PlannerView.swift`.
  - `PlannerModel` runs the flow: the progress steps, a cancel when a new search starts, and the last 5 searches (stored in UserDefaults).
  - `ClaudePlanner` sends the request, the person's interests and up to 60 upcoming events to `POST /api/planner`, with times in the phone's time zone, and maps the picks back to events. Unknown ids are dropped.
  - If there's no server, or the server answers `503 ai_unavailable` or can't be reached, `OnDevicePlanner` plans on the phone instead (keyword reading, ranking, wider search when nothing fits), and the screen says why.
  - Results show "Planned by Claude" or "Planned on your iPhone", a reason per pick, and a Join or Request button on each card.
  - Unit tests: `ios/PartnerTests/PlannerTests.swift` (Swift Testing, scheme `Partner`, ⌘U).
- **Still only on the phone (simulated):** sample events and people (can be hidden with Profile → Server → Show sample events), joining and RSVPs, join requests, chats, saved events, drafts, recurring events, cover photos and flyers.

Differences from our design:
- `client_architecture.md` is still blank, so there's nothing to compare against yet. The team should fill it in. The current state above can be the starting point.
- The app uses the category names listed in `API.md`, but the server's seed data uses different ones (`social`, `clubs`, ...). The team should pick one list.
- `docs/overview.md` says events show who's interested, while the Security section of `Prompt.md` says hosts only see counts. The app shows attendees today, but only from on-device sample data.
