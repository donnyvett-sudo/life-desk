#!/bin/zsh
# Builds the web client into ios/miniapp (bundled into the app as a folder reference).
set -euo pipefail
HERE="${0:A:h}"
SRC="${LIFE_AGENT_DIR:-$HOME/life-agent}/miniapp"
( cd "$SRC" && LIFE_DESK=1 npx vite build --outDir "$HERE/miniapp" --emptyOutDir >/dev/null )
echo "✓ $HERE/miniapp ($(git -C "$SRC" rev-parse --short HEAD))"
