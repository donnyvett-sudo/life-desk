# Life Desk

A personal life dashboard for Apple platforms: deadlines and exams, habits, focus timer, sleep, money, food, flashcards and a daily feed. Two native clients talk to your own backend.


## What is in this repo
| Part | What | Where |
|---|---|---|
| **Life Desk** (Mac) | SwiftUI shell, bundled web client in a WKWebView, study pages from a Markdown folder, optional Claude agent | `Sources/`, `build.sh` |
| **Life** (iPhone) | SwiftUI app, widget, Live Activity focus timer, HealthKit sleep sync, bundled web client | `ios/` |
| **Backend** (separate repo) | Life Agent: Supabase Postgres + Edge Functions (`api`), Telegram bot, the web "Mini App" both apps bundle | not in this repo |

```
iPhone "Life"  ----\
                     >--  HTTPS + personal token  -->  Life Agent (Supabase Edge Functions + Postgres)
Mac "Life Desk" ---/                                       |-- Telegram bot, Mini App
   |                                                       |-- AI features (Gemini, called by the backend)
   +-- study folder (Markdown), optional local `claude` CLI agent
```
Shared code: `Sources/Core` (no UI, unit-tested), `Sources/Shared` (theme). See `docs/ARCHITECTURE.md`.

## Requirements
- macOS 26 and Xcode with the iOS 26 SDK (the Mac app also builds with the Command Line Tools and plain `swiftc`).
- Node.js (builds the web client from the backend repo).
- Your own deployment of the Life Agent backend (Supabase project). This repo contains no server URL or keys.

## Configure and build
```
cp Config.local.xcconfig.example Config.local.xcconfig   # git-ignored; set your API URL, team id, bundle id prefix
./build.sh --miniapp /path/to/life-agent/miniapp          # Mac app -> build/LifeDesk.app (add --install to copy to ~/Applications)
./build.sh --test                                         # unit tests
```
iPhone: see `docs/IOS.md`. Mac details: `docs/INSTALL.md`.

## Pair a device
Create a personal token on your backend and paste it in Life Desk Settings. Without Telegram, use the `ingest_token` created by the backend repo's `scripts/bootstrap-owner.sql`; once one device is signed in, create pairing codes for the others (Settings > iPhone). With the optional Telegram bot, `/newtoken desk app` also works. For the iPhone, create a single-use pairing code in Life Desk (Settings > iPhone) and enter it on the Life connect screen. Tokens are stored in the Keychain and attached to requests only by the native layer; the web client never sees them.

## Sideload with a free Apple ID
Set `DEVELOPMENT_TEAM` (your personal team) and a unique `BUNDLE_ID_PREFIX` / `APP_GROUP_ID` in `Config.local.xcconfig`, open `ios/Life.xcodeproj`, choose your phone and Run. A free account's builds expire after 7 days, and some capabilities (HealthKit, App Groups, Live Activities) may require a paid program or manual enabling for your App ID. Details in `docs/IOS.md`.

## Privacy
- Your data lives in **your own Supabase project**; there is no vendor server. The apps send requests only to the API URL you configure.
- AI features (food photos, coaching, summaries) are performed by your backend, which calls Gemini with your own API key (the optional Mac study agent runs the local `claude` CLI); whatever you send to those features goes to those providers.
- The optional Mac Agent page runs the local `claude` CLI in your study folder under a restrictive allow-list (`AgentPolicy`), with no network tools and no secrets in its environment.
- The apps have no analytics or telemetry.

## Known limitations
- Built and tested against macOS 26 / iOS 26 only; CI uses a hosted runner that may lack that SDK.
- UI strings are mostly Russian with English translations; quick-entry parsing (weekdays, phrases) is Russian-only.
- Currencies are limited to CNY, KZT and USD; some screens fall back to CNY when the backend gives no currency.
- The default workspace folder is `~/Documents/Study Workspace` and course-specific features (AI-policy table, chat sync via QQ/WeChat) ship empty or optional.

## License
MIT, see `LICENSE`. Contributions: `CONTRIBUTING.md`. Security reports: `SECURITY.md`.
