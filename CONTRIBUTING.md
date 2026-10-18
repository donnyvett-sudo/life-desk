# Contributing

Issues and pull requests are welcome.

- Run `./build.sh --test` before sending a PR; it needs no network and no personal data. CI runs the same command.
- Keep `Sources/Core` free of UI so it stays testable. New logic there gets a check in `Sources/Tests`.
- UI colours come from `design/tokens.json` (`scripts/check-tokens.py` verifies contrast).
- Never commit real URLs, tokens, team ids, bundle ids or personal data. Use `Config.local.xcconfig` for anything deployment-specific, and fake data in tests.
- Small, focused PRs with a short description of the why.
