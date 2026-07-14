#!/bin/bash
set -euo pipefail

# Build + assemble a runnable dev .app bundle and launch it via LaunchServices.
#
# Why this exists: running the bare SPM binary (.build/*/GRump) from a script
# or background process never registers with LaunchServices, so the app can
# draw windows but can NEVER become the key application — it looks alive but
# ignores all keyboard input. Launching a signed .app bundle with `open` is
# the only reliable path. (An unsigned bundle gets app-translocated to a
# read-only path and sticks on the splash screen — hence the ad-hoc signing.)
#
# Usage:
#   ./scripts/dev-app.sh              # release build (default — debug is
#                                     # painfully slow on Intel Macs)
#   ./scripts/dev-app.sh --debug      # unoptimized debug build
#   ./scripts/dev-app.sh --no-launch  # assemble only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

CONFIG="release"
LAUNCH=true
for arg in "$@"; do
  case $arg in
    --debug) CONFIG="debug" ;;
    --no-launch) LAUNCH=false ;;
    *) echo "Usage: $0 [--debug] [--no-launch]"; exit 1 ;;
  esac
done

echo "▸ Building ($CONFIG, native arch)..."
swift build -c "$CONFIG" -j "$(sysctl -n hw.ncpu)"

BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)
APP="dist-dev/G-Rump.app"

echo "▸ Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GRump" "$APP/Contents/MacOS/GRump"
chmod +x "$APP/Contents/MacOS/GRump"
cp Sources/GRump/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[ -d "$BIN_DIR/GRump_GRump.bundle" ] && cp -R "$BIN_DIR/GRump_GRump.bundle" "$APP/Contents/Resources/"
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/GRump" 2>/dev/null || true
fi
[ -f Sources/GRump/Resources/AppIcon.icns ] && \
  cp Sources/GRump/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Ad-hoc signing (inside-out)..."
FW="$APP/Contents/Frameworks/Sparkle.framework"
if [ -d "$FW" ]; then
  for xpc in "$FW"/Versions/B/XPCServices/*.xpc; do
    [ -d "$xpc" ] && codesign --force --timestamp --sign - "$xpc"
  done
  [ -d "$FW/Versions/B/Updater.app" ] && codesign --force --timestamp --sign - "$FW/Versions/B/Updater.app"
  [ -f "$FW/Versions/B/Autoupdate" ] && codesign --force --timestamp --sign - "$FW/Versions/B/Autoupdate"
  codesign --force --timestamp --sign - "$FW"
fi
codesign --force --timestamp --entitlements GRump.entitlements --sign - "$APP"
codesign --verify "$APP"
echo "✓ $APP ready"

if $LAUNCH; then
  echo "▸ Launching..."
  open "$APP"
fi
