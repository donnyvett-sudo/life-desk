# Life Desk

Mac app (SwiftUI + WKWebView, plain `swiftc`, no Xcode project) and iPhone app "Life" (`ios/`, Xcode project). Both are clients of the Life Agent backend (separate repo).

- `./build.sh` builds `build/LifeDesk.app`; `./build.sh --test` runs the Core unit tests (no network).
- `Sources/Core` = no UI (Config, Keychain, API client, Claude runner); `Sources/Shared` = theme/palette; `Sources/App` = Mac views; `ios/` = iPhone app and widget.
- Local configuration lives in git-ignored `Config.local.xcconfig` (copy the `.example`). Never commit URLs, tokens, team ids or bundle ids of a real deployment.
- The personal token goes to Keychain only; it never goes to logs, chat or git.
- See `docs/ARCHITECTURE.md`, `docs/DATA-CONTRACT.md`, `docs/DESIGN.md`.
