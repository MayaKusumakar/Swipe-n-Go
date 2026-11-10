# Swipe-n-Go


**Never do it alone.** Partner is like Tinder, but for activities. Swipe on plans other people are hosting (a sunrise run, a concert, a taco crawl, a day trip), or host your own and let people come to you.

Native SwiftUI prototype for iOS 26+, built with Liquid Glass.

## Run it
1. Open `Partner.xcodeproj` in Xcode 26 or later.
2. Pick an iPhone simulator and press **⌘R**.

If you're running on a real device, set your Team under *Signing & Capabilities*. If you change `project.yml`, regenerate the project with `xcodegen generate`.

## What's in it
| Tab | What you can do |
|---|---|
| **Onboarding** | Animated welcome, name/age/pronouns, pick 3+ interests, permissions |
| **Discover** | Swipe deck: right to join, left to pass, up to save. Undo, a "For You" ranking, category filters, a distance radius, and a celebration screen when you join |
| **Explore** | Map with category pins and a list grouped by day. Search and filter chips |
| **Activity detail** | Stretchy hero, host card, attendees, map and directions, share, save, join or request, leave |
| **Host a plan** | Live preview, title suggestions, quick time presets, real place search (MapKit), group size and level, an approval toggle |
| **Plans** | "Next up" countdown, Going / Hosting / Saved, and approve or decline join requests |
| **Chats** | A group chat for every plan plus DMs, typing indicator, quick replies, unread badges |
| **Profile** | Stats, interests, edit avatar and bio, preferences, safety center, report/block |

## Prototype notes
- **No backend yet.** The people and plans are realistic sample data around Davis, CA. Everything you do is saved on the device (`AppStore.swift` persists to JSON).
- **The other side is simulated.** Hosts approve requests after a few seconds, someone requests to join plans you host, and people reply in chat.
- Profile → **Refresh demo content** gets you fresh plans. **Sign out & reset** restarts onboarding.
- Debug launch arguments for screenshots: `-demo` (skip onboarding), `-joined`, `-detail`, `-chat`, `-tab <discover|explore|plans|chats|profile>`.

## Code map
```
Partner/
  App/        PartnerApp, RootView, tab bar
  Models/     Activity, Person, Conversation, sample data
  Store/      AppStore: state, persistence, simulation
  Design/     Shared components (avatars, chips, FlowLayout, buttons, banner)
  Views/      Onboarding, Discover, Explore, Activity, Create, Plans, Chats, Profile
```

Next steps for a real product: a backend (e.g. Firebase or Supabase), auth, push notifications, real location, and moderation.
