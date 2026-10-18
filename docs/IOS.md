# Building the iPhone app ("Life")

Requirements: Xcode with the iOS 26 SDK, an Apple ID (a free one is enough for sideloading), Node.js, a checkout of the Life Agent backend repo.

1. `cp Config.local.xcconfig.example Config.local.xcconfig` and set:
   - `LIFE_API_BASE`: your backend API URL (`https:/$()/` for the scheme, see the example).
   - `DEVELOPMENT_TEAM`: your Team ID (Xcode > Settings > Accounts > your team).
   - `BUNDLE_ID_PREFIX`: unique to you, e.g. `com.yourname.lifedesk`. The app becomes `<prefix>.life`, the widget `<prefix>.life.focus`.
   - `APP_GROUP_ID`: e.g. `group.com.yourname.lifedesk`.
2. Build the bundled web client: `LIFE_AGENT_DIR=/path/to/life-agent ios/build-miniapp.sh` (creates the git-ignored `ios/miniapp`).
3. Open `ios/Life.xcodeproj`, select the Life scheme and your iPhone, press Run.
   With a free Apple ID the app expires after 7 days and must be re-installed; HealthKit, App Groups and Live Activities may need the capabilities to be enabled for your App ID in Xcode (Signing & Capabilities).
4. Pair: in Life Desk (Mac) Settings > iPhone create a pairing code, then enter it on the iPhone's connect screen (or paste a token). Pairing codes are single-use.

Simulator check without signing: `xcodebuild -project ios/Life.xcodeproj -scheme Life -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
