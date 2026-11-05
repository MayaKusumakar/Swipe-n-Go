# Client Architecture (LLM notes)

LLM keeps this updated as the design changes. Our version is in client_architecture.md.

Current state (2026-11-04):
- Android app in `android/`: Kotlin + Jetpack Compose (team decision). Package `com.swipengo.app`, minSdk 26 (for java.time), target/compile SDK 37. AGP 9.4.1, Kotlin 2.2.10, Gradle 9.6.0, matching the Android Studio template on the dev machine.
- One screen: the swipe deck (`ui/deck/SwipeDeckScreen.kt`).
  - Drag a card left or right past 30% of its width, or use the Skip / Interested buttons. Both animate the card off screen.
  - Tapping a card expands the full description. The next card peeks underneath.
  - States: Loading, Empty (Refresh), Error with the server's message (Retry), Deck, and "all caught up" (Start over).
  - The image area is a colored placeholder showing the category, because `image_url` is null for now.
- Layers:
  - `data/EventsApi.kt`: the interface plus `EventsApiException` (Network / Server / MalformedResponse).
  - `data/HttpEventsApi.kt`: `HttpURLConnection` on Dispatchers.IO, 10s timeouts. No Retrofit/OkHttp.
  - `data/EventJsonParser.kt`: org.json (built into Android) parsing into `Event`.
  - `ui/deck/DeckViewModel.kt`: a `StateFlow<DeckUiState>` that loads 20 events and tracks the swipe index plus the IDs swiped right.
  - `MainActivity.kt`: builds `HttpEventsApi(BuildConfig.API_BASE_URL)` by hand. No DI framework.
- State management: ViewModel + StateFlow. The UI composable `SwipeDeckContent` is stateless.
- Server: `GET /api/events?limit=20` (see API.llm.md). The base URL comes from the Gradle property `swipeNGo.apiBaseUrl`, default `http://localhost:8080` plus `adb reverse tcp:8080 tcp:8080`.
  - Why not 10.0.2.2: on the Android 17 emulator (local network protection flag on), apps targeting SDK 37 can't reach private IPs without the local-network runtime permission. Connections hang, then time out. This was found on Medium_Phone (API 37.2) on 2026-11-04.
- Cleartext HTTP is only allowed to 10.0.2.2/localhost/127.0.0.1 (`res/xml/network_security_config.xml`).
- Local storage: none. Swipes live in memory only and are lost on restart.

Differences from our design:
- client_architecture.md is still blank, so there's nothing to compare against yet.
- Prompt.md asks for an event image on each card. That's a placeholder until the server has images.
- Swipes aren't sent to the server (proposal P3 in decisions.md).
