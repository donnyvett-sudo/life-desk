# Security policy

Please report vulnerabilities privately, not in a public issue: use GitHub's "Report a vulnerability" (private security advisory) on this repository. Include steps to reproduce and the affected version/commit. You can expect an acknowledgement within a few days.

Areas where reports matter most: handling of the personal token (Keychain, the native bridge that keeps it out of page JavaScript), the agent sandbox policy (`Sources/Core/AgentPolicy.swift`), and the web view's CSP and link handling.

If you find a secret that was committed by mistake, report it the same way so it can be rotated.

## Tokens and the Mac agent relay

An `admin` or `*` API token can queue and read jobs on the Mac agent relay, which makes your Mac execute work. Issue the `agent` scope only to the Mac running Life Desk. Give Shortcuts and health checks `ingest`-scope tokens only. Treat `*` tokens like a password, and rotate them if they are ever exposed.
