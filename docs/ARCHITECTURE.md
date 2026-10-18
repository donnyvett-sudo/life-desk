# Architecture

```
Study Workspace folder (Markdown)  <->  Life Desk (SwiftUI)  <->  Bot API (Supabase Edge Functions)  <->  Telegram, Mini App
                                      |  WKWebView: Mini App (bundled, lifedesk://app)
                                      |  claude CLI (Agent page, sandboxed by AgentPolicy)
```

- **Sources/Core** has no UI: bot client and models, deadline logic, Markdown parsing, Focus logic, Claude runner and policy, workspace snapshots, Keychain, Config, Palette. Everything here is tested by `./build.sh --test`.
- **Sources/App** is SwiftUI: pages, Settings, the web view and its native bridge.
- **Token**: Keychain (or `the token file (see Config.tokenFile)`); `BotAPI.raw` is the only place that attaches it. The Mini App talks to the bot only through the `lifedesk` message bridge, so the token never enters page JavaScript. The page has a CSP with `connect-src 'self'`.
- **Agent**: `claude -p` in the workspace with an allow/deny list (`AgentPolicy`), file edits limited to a few paths, a snapshot before each run and a diff card with revert.
- **Offline**: the bot overview is cached (`study.json`, 0600); pages show the reason and the age of the data.

## Threat model in one paragraph
Course chats are written by other people and the Agent reads them, so anything the Agent can do must be safe even if a chat message tries to instruct it: no network tools, no writes outside the allowed paths, no secrets in its environment, helper tool with path checks. The web view loads only the bundled page; external links open only on a user click.

## Tests
`./build.sh --test` compiles Core and Tests together and runs them (no network, no personal data needed). `Sources/Tests/probe.sh` runs real-`claude` safety probes by hand.
