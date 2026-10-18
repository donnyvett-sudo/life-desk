#!/bin/zsh
# Builds Life Desk.app with plain swiftc (Xcode Command Line Tools are enough).
#   ./build.sh            → build/LifeDesk.app
#   ./build.sh --install  → also copies it to ~/Applications and opens it
#   ./build.sh --miniapp <path-to-life-agent/miniapp>   build the Mini App from that folder
#   ./build.sh --skip-miniapp                           reuse build/miniapp from the last build
set -euo pipefail
HERE="${0:A:h}"; cd "$HERE"
MINIAPP="${LIFE_AGENT_DIR:-$HOME/life-agent}/miniapp"   # a checkout of the Life Agent backend repo
SKIP_MINIAPP=0; INSTALL=0; TEST=0
while (( $# )); do
  case "$1" in
    --miniapp) (( $# >= 2 )) || { echo "--miniapp needs a path"; exit 2; }; MINIAPP="$2"; shift ;;
    --skip-miniapp) SKIP_MINIAPP=1 ;;
    --install) INSTALL=1 ;;
    --test) TEST=1 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
  shift
done
ARCH="$(uname -m)"

# Local configuration (git-ignored): cp Config.local.xcconfig.example Config.local.xcconfig and edit.
# Only LIFE_API_BASE is used here; the other keys are for the iOS project.
API_BASE=""
if [[ -f Config.local.xcconfig ]]; then
  API_BASE="$(sed -n 's/^LIFE_API_BASE[[:space:]]*=[[:space:]]*//p' Config.local.xcconfig | head -1 | sed 's/\$()//g')"
fi
[[ -n "$API_BASE" ]] || echo "! no LIFE_API_BASE in Config.local.xcconfig: the API URL must be entered in Settings after launch."

if (( TEST )); then
  mkdir -p build
  swiftc -swift-version 5 -target "$ARCH-apple-macos26" -module-name LifeDeskTests \
    Sources/Core/*.swift Sources/Tests/*.swift -o build/tests
  exec build/tests
fi

if (( SKIP_MINIAPP )); then
  [[ -d build/miniapp ]] || { echo "no build/miniapp yet: run once without --skip-miniapp"; exit 1; }
else
  echo "→ Mini App ($MINIAPP)"
  [[ -f "$MINIAPP/package.json" ]] || { echo "Mini App not found at $MINIAPP (use --miniapp <path> or LIFE_AGENT_DIR)"; exit 1; }
  ( cd "$MINIAPP" && { [[ -d node_modules ]] || npm ci --ignore-scripts; } && LIFE_DESK=1 npx vite build --outDir "$HERE/build/miniapp" --emptyOutDir >/dev/null )
  git -C "$MINIAPP" rev-parse --short HEAD > build/miniapp/VERSION 2>/dev/null || echo unknown > build/miniapp/VERSION
fi

echo "→ LifeDesk"
swiftc -swift-version 5 -target "$ARCH-apple-macos26" -O -parse-as-library -module-name LifeDesk \
  Sources/Core/*.swift Sources/Shared/*.swift Sources/App/*.swift -o build/LifeDesk

APP="build/LifeDesk.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/LifeDesk "$APP/Contents/MacOS/"
sed "s|__LIFE_API_BASE__|$API_BASE|" Info.plist.in > "$APP/Contents/Info.plist"
cp -R build/miniapp "$APP/Contents/Resources/miniapp"
[[ -f build/AppIcon.icns ]] || zsh Icon/make-icon.sh build/AppIcon.icns
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Extended attributes (provenance, Finder info) make codesign refuse the bundle.
xattr -cr "$APP" 2>/dev/null || true
# A stable local identity keeps Keychain access across rebuilds (scripts/make-signing-identity.sh creates it).
SIGN="${LIFE_DESK_SIGN_IDENTITY:-Life Desk Local}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$SIGN\"" && codesign --force --sign "$SIGN" "$APP" 2>/dev/null; then
  echo "✓ signed with \"$SIGN\""
else
  echo "! no stable signing identity: signed ad-hoc (the Keychain will ask for the password after each rebuild)."
  echo "  Create one once: scripts/make-signing-identity.sh"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "! codesign failed"
fi
echo "✓ $APP"
if (( INSTALL )); then
  pkill -x LifeDesk 2>/dev/null || true
  mkdir -p ~/Applications; rm -rf ~/Applications/LifeDesk.app; cp -R "$APP" ~/Applications/
  open ~/Applications/LifeDesk.app
fi
