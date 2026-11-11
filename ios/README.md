# Swipe-n-Go


**Never do it alone.** Partner is like Tinder, but for activities. Swipe on plans other people are hosting (a sunrise run, a concert, a taco crawl, a day trip), or host your own and let people come to you.

Native SwiftUI prototype for iOS 26+, built with Liquid Glass.

## Run it
1. Open `Partner.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator and press **⌘R**.

If you're running on a real device, set your Team under *Signing & Capabilities*. If you change `project.yml`, regenerate the project with `xcodegen generate`.

## Share events between phones (backend)
Events you post appear on everyone's phone through the Flask server in `../backend`. See `../docs/API.md`.

1. Start the server on your Mac:
   ```
   cd backend
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   EVENT_STORE=memory flask --app main run --host 0.0.0.0 --port 8080
   ```
2. **Simulator:** nothing to set, it uses `http://localhost:8080`.
   **iPhone:** connect it to the same Wi‑Fi as the Mac, open Profile → **Server**, and enter `http://<Mac's IP>:8080`. Find the IP under System Settings → Wi‑Fi → Details. Allow "find devices on your local network" when iOS asks.
3. Post a plan with **＋ Host**. Other phones pick it up within 15 seconds, or right away with pull-to-refresh in Explore's list.

Turn off Profile → Server → **Show sample events** to see only real posts. `EVENT_STORE=memory` forgets posts when the server stops. For permanent storage, deploy to App Engine with Datastore (`backend/app.yaml`).

## AI planner ("I'm free…")
Tap **I'm free…** at the start of Discover's filter row, then say when you're free, e.g. *"free tomorrow after 5, want something active but I don't know anyone"*. You get up to 5 plans that fit, each with a reason and a Join button.

- **With Claude:** copy `backend/.env.example` to `backend/.env`, paste your key into `ANTHROPIC_API_KEY=`, and restart the server. `flask run` reads `.env`. Never commit `.env`.
- **Without a key or server,** the app plans on the phone and says so. The demo never breaks.
- Run the planner tests with **⌘U** in Xcode, and the server tests with `python -m pytest` in `backend/`.

## What's in it
| Tab | What you can do |
|---|---|
| **Onboarding** | Animated welcome, name/age/pronouns, pick 3+ interests, permissions |
| **Discover** | Swipe deck: right to join, left to pass, up to save. Undo, a "For You" ranking, category filters, a distance radius, a celebration screen when you join, and the **I'm free…** AI planner |
| **Explore** | Map with category pins and a list grouped by day. Search and filter chips |
| **Activity detail** | Stretchy hero, host card, attendees, map and directions, share, save, join or request, leave |
| **Host a plan** | Live preview, title suggestions, quick time presets, real place search (MapKit), group size and level, an approval toggle |
| **Plans** | "Next up" countdown, Going / Hosting / Saved, and approve or decline join requests |
| **Chats** | A group chat for every plan plus DMs, typing indicator, quick replies, unread badges |
| **Profile** | Stats, interests, edit avatar and bio, preferences, safety center, report/block |

## Prototype notes
- **Shared events go through the backend.** Joining, chats, requests and saved plans are still only on the device (`AppStore.swift` persists to JSON). The built-in sample people and plans are around Davis, CA.
- **The other side is simulated.** Hosts approve requests after a few seconds, someone requests to join plans you host, and people reply in chat.
- Profile → **Refresh demo content** gets you fresh plans. **Sign out & reset** restarts onboarding.
- Debug launch arguments for testing: `-demo` (skip onboarding), `-joined`, `-detail`, `-chat`, `-host`, `-photo`, `-onboarding [-step N] [-ask]`, `-server <url>`, `-noSamples`, `-samples`, `-hostTest`, `-plan "<request>"`, `-tab <discover|explore|plans|chats|profile>`.

## Code map
```
Partner/
  App/        PartnerApp, RootView, tab bar
  Models/     Activity, Person, Conversation, sample data
  Store/      AppStore: state, persistence, simulation; EventServer + AppStore+Server: backend sync
  Design/     Shared components (avatars, chips, FlowLayout, buttons, banner)
  Views/      Onboarding, Discover, Explore, Activity, Create, Plans, Chats, Profile
```

Next steps: deploy the backend to App Engine, @ucdavis.edu sign-in, RSVPs and chats on the server, image uploads, push notifications, and moderation.
