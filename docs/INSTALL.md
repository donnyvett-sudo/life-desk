# Installing Life Desk (Mac)

Life Desk is a macOS 26 app for one person: a native shell around your own Life Agent backend and, optionally, a folder of Markdown study notes.

## You need
- macOS 26, Xcode (or the Command Line Tools: `xcode-select --install`), Node.js (for the Mini App build).
- Your own Life Agent backend (a Supabase project plus the Edge Function `api`) and a checkout of its repo, which contains the `miniapp/` web client. See the backend repo's setup guide.
- A personal token from the backend (create one with the backend's token command, e.g. `/newtoken desk app` in the bot chat).
- Optional, for the Agent page: Claude Code (`claude`), signed in with `claude auth login`.
- Optional, for the Study pages: a workspace folder with `resources/<course>/assignments.md` (see DATA-CONTRACT.md).

## Configure
```
cp Config.local.xcconfig.example Config.local.xcconfig
```
Edit `LIFE_API_BASE` (the `.../functions/v1/api` URL of your project; write `https:/$()/` for the scheme). The file is git-ignored. If you skip it, enter the URL in Settings after the first launch.

## Build and install
```
./build.sh --miniapp /path/to/life-agent/miniapp --install     # or set LIFE_AGENT_DIR
./build.sh --test                                              # unit tests, no network
```
Without a stable signing identity the Keychain asks for your password after each rebuild.
Create one once with `scripts/make-signing-identity.sh` (self-signed, local to your Mac).

## First run
1. Open Settings (Cmd+,).
2. Bot: paste the API URL (if not built in) and the token, press Test connection.
3. Workspace: choose your study folder (Study pages stay empty without it).
4. Agent: press Check; it must print the claude version.

Environment overrides for a test copy: `LIFE_DESK_WORKSPACE`, `LIFE_DESK_API`.
