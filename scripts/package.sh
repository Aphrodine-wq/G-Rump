#!/bin/bash
set -euo pipefail

# G-Rump 2.0 macOS Packaging Script
# Creates a properly signed .app bundle and optionally a .dmg with notarization.
#
# IMPORTANT: All builds are at minimum ad-hoc codesigned to prevent macOS
# app translocation, which moves unsigned .app bundles to a randomized
# read-only path and breaks resource loading at runtime.
#
# Usage:
#   ./scripts/package.sh                          # Build .app (ad-hoc signed)
#   ./scripts/package.sh --sign                    # Build + Developer ID sign
#   ./scripts/package.sh --sign --dmg              # Build + sign + create .dmg
#   ./scripts/package.sh --sign --dmg --notarize   # Build + sign + .dmg + notarize
#   ./scripts/package.sh --clean                   # Force clean rebuild
#   ./scripts/package.sh --skip-build              # Re-package from existing binary
#
# Prerequisites:
#   brew install create-dmg    (required for --dmg)
#
# Environment variables (for signing/notarization):
#   DEVELOPER_ID    — "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID        — your Apple ID email
#   TEAM_ID         — your Apple Developer Team ID
#   APP_PASSWORD    — app-specific password for notarytool

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="G-Rump"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
ENTITLEMENTS="$PROJECT_DIR/GRump.entitlements"
INFO_PLIST="$PROJECT_DIR/Sources/GRump/Info.plist"
ICON_SOURCE="$PROJECT_DIR/Sources/GRump/Resources/AppIcon.icns"
ASSETS_DIR="$PROJECT_DIR/Sources/GRump/Resources/Assets.xcassets/AppIcon.appiconset"

DO_SIGN=false
DO_DMG=false
DO_NOTARIZE=false
DO_CLEAN=false
SKIP_BUILD=false
DO_ZIP=false

for arg in "$@"; do
    case "$arg" in
        --sign) DO_SIGN=true ;;
        --dmg) DO_DMG=true ;;
        --zip) DO_ZIP=true ;;
        --notarize) DO_NOTARIZE=true ;;
        --clean) DO_CLEAN=true ;;
        --skip-build) SKIP_BUILD=true ;;
        --help|-h)
            echo "Usage: $0 [--sign] [--zip] [--dmg] [--notarize] [--clean] [--skip-build]"
            echo ""
            echo "  --sign       Code sign with Developer ID (requires DEVELOPER_ID env var)"
            echo "  --zip        Create a distributable .zip of the .app (after signing/stapling)"
            echo "  --dmg        Create .dmg disk image (requires create-dmg)"
            echo "  --notarize   Submit to Apple for notarization (requires APPLE_ID, TEAM_ID, APP_PASSWORD)"
            echo "  --clean      Force clean rebuild (removes .build and dist)"
            echo "  --skip-build Re-package from existing binary (skip swift build)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Run $0 --help for usage."
            exit 1
            ;;
    esac
done

# ── Pre-flight checks ─────────────────────────────────
if $DO_DMG; then
    if ! command -v create-dmg &>/dev/null; then
        echo "✗ create-dmg is required for DMG creation."
        echo "  Install it with: brew install create-dmg"
        exit 1
    fi
fi

if $DO_NOTARIZE && ! $DO_SIGN; then
    echo "✗ Notarization requires signing. Add --sign flag."
    exit 1
fi

if $DO_SIGN && [ -z "${DEVELOPER_ID:-}" ]; then
    echo "✗ DEVELOPER_ID not set. Example:"
    echo '  export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"'
    exit 1
fi

if $DO_NOTARIZE; then
    if [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ]; then
        echo "✗ Notarization requires these environment variables:"
        echo "  APPLE_ID     — your Apple ID email"
        echo "  TEAM_ID      — your Apple Developer Team ID"
        echo "  APP_PASSWORD — app-specific password"
        echo ""
        echo "  Tip: create .env.local and run: source .env.local"
        exit 1
    fi
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  G-Rump 2.0 Packaging"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

JOBS="$(sysctl -n hw.ncpu)"
cd "$PROJECT_DIR"

# ── Step 1: Clean (if requested) ──────────────────────
if $DO_CLEAN; then
    echo "▸ Cleaning build artifacts..."
    rm -rf .build dist
    echo "✓ Cleaned .build/ and dist/"
    echo ""
fi

# ── Step 2: Build universal release binary ────────────
# Resolve the binary output path dynamically via --show-bin-path
# so we don't hardcode a path that may differ across Swift versions.
BUILD_FLAGS="-c release --arch arm64 --arch x86_64 -j $JOBS"

if $SKIP_BUILD; then
    echo "▸ Skipping build (--skip-build)..."
    BIN_DIR=$(swift build $BUILD_FLAGS --show-bin-path 2>/dev/null)
    BINARY="$BIN_DIR/GRump"
    if [ ! -f "$BINARY" ]; then
        echo "✗ No existing binary found at $BINARY"
        echo "  Run without --skip-build first."
        exit 1
    fi
    echo "  → Using existing binary: $BINARY"
else
    echo "▸ Building universal release binary (arm64 + x86_64)..."
    START_TIME=$(date +%s)

    if ! swift build $BUILD_FLAGS 2>&1 | tail -20; then
        echo ""
        echo "✗ Build failed. Check the errors above."
        echo "  Try: ./scripts/package.sh --clean"
        exit 1
    fi

    BIN_DIR=$(swift build $BUILD_FLAGS --show-bin-path 2>/dev/null)
    BINARY="$BIN_DIR/GRump"

    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    echo "  → Build completed in ${BUILD_TIME}s"
fi

if [ ! -f "$BINARY" ]; then
    echo "✗ Binary not found at $BINARY"
    exit 1
fi

# Verify universal binary
ARCHS=$(lipo -archs "$BINARY" 2>/dev/null || echo "unknown")
echo "✓ Binary: $BINARY"
echo "  → Architectures: $ARCHS"
if [[ "$ARCHS" != *"arm64"* ]] || [[ "$ARCHS" != *"x86_64"* ]]; then
    echo "⚠ Warning: Binary may not be universal. Expected arm64 + x86_64, got: $ARCHS"
fi
echo ""

# ── Step 3: Assemble .app bundle ──────────────────────
echo "▸ Creating .app bundle..."

# Always start fresh to avoid stale artifacts
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/GRump"
chmod +x "$APP_BUNDLE/Contents/MacOS/GRump"

# Copy Info.plist
if [ ! -f "$INFO_PLIST" ]; then
    echo "✗ Info.plist not found at $INFO_PLIST"
    exit 1
fi
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
echo "  → Info.plist"

# Write PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy bundled resources (skills, privacy manifest, etc.)
RESOURCE_BUNDLE="$BIN_DIR/GRump_GRump.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
    SKILL_COUNT=$(find "$APP_BUNDLE/Contents/Resources/GRump_GRump.bundle" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
    echo "  → Resource bundle ($SKILL_COUNT skills)"
else
    echo "⚠ Warning: SPM resource bundle not found at $RESOURCE_BUNDLE"
    echo "  Skills and bundled resources will be missing."
fi

# Copy Sparkle.framework (required runtime dependency for auto-updates)
SPARKLE_FW="$BIN_DIR/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
    # Ensure the binary's rpath includes the Frameworks directory
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP_BUNDLE/Contents/MacOS/GRump" 2>/dev/null || true
    echo "  → Sparkle.framework"
else
    echo "⚠ Warning: Sparkle.framework not found at $SPARKLE_FW"
    echo "  Auto-update functionality will be missing."
fi

# Copy or generate app icon
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "  → AppIcon.icns (existing)"
elif [ -d "$ASSETS_DIR" ]; then
    echo "  → Generating AppIcon.icns from xcassets PNGs..."
    ICONSET_TMP=$(mktemp -d)
    ICONSET_DIR="$ICONSET_TMP/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    cp "$ASSETS_DIR/16.png"   "$ICONSET_DIR/icon_16x16.png"
    cp "$ASSETS_DIR/32.png"   "$ICONSET_DIR/icon_16x16@2x.png"
    cp "$ASSETS_DIR/32.png"   "$ICONSET_DIR/icon_32x32.png"
    cp "$ASSETS_DIR/64.png"   "$ICONSET_DIR/icon_32x32@2x.png"
    cp "$ASSETS_DIR/128.png"  "$ICONSET_DIR/icon_128x128.png"
    cp "$ASSETS_DIR/256.png"  "$ICONSET_DIR/icon_128x128@2x.png"
    cp "$ASSETS_DIR/256.png"  "$ICONSET_DIR/icon_256x256.png"
    cp "$ASSETS_DIR/512.png"  "$ICONSET_DIR/icon_256x256@2x.png"
    cp "$ASSETS_DIR/512.png"  "$ICONSET_DIR/icon_512x512.png"
    cp "$ASSETS_DIR/1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_TMP"
    echo "  → AppIcon.icns (generated)"
else
    echo "⚠ Warning: No app icon found. App will use default icon."
fi

echo "✓ App bundle assembled: $APP_BUNDLE"
echo ""

# ── Step 4: Code sign ─────────────────────────────────
# CRITICAL: Always sign. Without at least an ad-hoc signature, macOS
# applies app translocation — moving the .app to a randomized read-only
# path at launch. This breaks Bundle.main.resourceURL and causes the app
# to get stuck on the splash screen (resources like skills, conversations
# data, etc. become inaccessible).
#
# NOTE: We avoid --deep and instead sign each embedded component individually,
# inside-out. Apple recommends this approach because --deep does not
# guarantee correct signing order and can produce invalid signatures on
# nested bundles (frameworks, XPC services, helper apps).
#
# Signing order: innermost components first, outermost (.app) last.
sign_component() {
    local identity="$1"
    local path="$2"
    local with_entitlements="${3:-false}"
    local with_runtime="${4:-false}"

    local flags=(--force --timestamp)
    if [ "$with_runtime" = true ]; then
        flags+=(--options runtime)
    fi
    if [ "$with_entitlements" = true ] && [ -f "$ENTITLEMENTS" ]; then
        flags+=(--entitlements "$ENTITLEMENTS")
    fi
    flags+=(--sign "$identity" "$path")

    codesign "${flags[@]}"
}

if $DO_SIGN; then
    echo "▸ Code signing with Developer ID: $DEVELOPER_ID"
    SIGN_IDENTITY="$DEVELOPER_ID"
else
    echo "▸ Ad-hoc code signing (prevents app translocation)..."
    SIGN_IDENTITY="-"
fi

# Sign Sparkle XPC services (innermost)
SPARKLE_FW_BUNDLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW_BUNDLE" ]; then
    echo "  → Signing Sparkle XPC services..."
    for xpc in "$SPARKLE_FW_BUNDLE"/Versions/B/XPCServices/*.xpc; do
        [ -d "$xpc" ] && sign_component "$SIGN_IDENTITY" "$xpc" false "$DO_SIGN"
    done

    # Sign Sparkle Updater.app helper
    UPDATER_APP="$SPARKLE_FW_BUNDLE/Versions/B/Updater.app"
    if [ -d "$UPDATER_APP" ]; then
        echo "  → Signing Sparkle Updater.app..."
        sign_component "$SIGN_IDENTITY" "$UPDATER_APP" false "$DO_SIGN"
    fi

    # Sign Sparkle Autoupdate binary
    AUTOUPDATE_BIN="$SPARKLE_FW_BUNDLE/Versions/B/Autoupdate"
    if [ -f "$AUTOUPDATE_BIN" ]; then
        echo "  → Signing Sparkle Autoupdate..."
        codesign --force --timestamp --sign "$SIGN_IDENTITY" "$AUTOUPDATE_BIN"
    fi

    # Sign Sparkle framework itself
    echo "  → Signing Sparkle.framework..."
    sign_component "$SIGN_IDENTITY" "$SPARKLE_FW_BUNDLE" false "$DO_SIGN"
fi

# Sign resource bundles
for bundle in "$APP_BUNDLE"/Contents/Resources/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "  → Signing $(basename "$bundle")..."
        sign_component "$SIGN_IDENTITY" "$bundle" false "$DO_SIGN"
    fi
done

# Sign the main app bundle (outermost, with entitlements + hardened runtime)
echo "  → Signing G-Rump.app..."
sign_component "$SIGN_IDENTITY" "$APP_BUNDLE" true "$DO_SIGN"

# Verify signature
echo "▸ Verifying signature..."
if codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1; then
    echo "✓ Code signature verified"
else
    echo "✗ Code signature verification failed"
    echo "  The app may not launch correctly from Finder."
    exit 1
fi

# Deep verification (checks all nested components)
echo "▸ Deep verification of all components..."
if codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1; then
    echo "✓ Deep signature verification passed"
else
    echo "⚠ Deep verification found issues (may still work for ad-hoc)"
fi
echo ""

# ── Step 5: Create .dmg ──────────────────────────────
if $DO_DMG; then
    echo "▸ Creating .dmg..."
    rm -f "$DMG_PATH"

    create-dmg \
        --volname "$APP_NAME" \
        --volicon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 175 190 \
        --app-drop-link 425 190 \
        --hide-extension "$APP_NAME.app" \
        "$DMG_PATH" \
        "$APP_BUNDLE" \
        2>&1 || true

    if [ -f "$DMG_PATH" ]; then
        echo "✓ DMG created: $DMG_PATH"
    else
        echo "✗ DMG creation failed"
        exit 1
    fi

    # Sign the DMG too
    if $DO_SIGN && [ -n "${DEVELOPER_ID:-}" ]; then
        echo "▸ Signing .dmg..."
        codesign --force --sign "$DEVELOPER_ID" "$DMG_PATH"
        echo "✓ DMG signed"
    fi
    echo ""
fi

# ── Step 6: Notarize ─────────────────────────────────
if $DO_NOTARIZE; then
    NOTARIZE_TARGET="$DMG_PATH"
    if [ ! -f "$NOTARIZE_TARGET" ]; then
        # If no DMG, zip the .app for notarization
        NOTARIZE_TARGET="$DIST_DIR/${APP_NAME}.zip"
        echo "▸ Creating zip for notarization..."
        ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_TARGET"
    fi

    echo "▸ Submitting for notarization (this may take several minutes)..."
    SUBMIT_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_TARGET" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait 2>&1) || true

    echo "$SUBMIT_OUTPUT"

    # Extract submission ID for log retrieval
    SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -o 'id: [a-f0-9-]*' | head -1 | sed 's/id: //')

    if echo "$SUBMIT_OUTPUT" | grep -qi "accepted\|success"; then
        echo "✓ Notarization accepted"
    else
        echo "✗ Notarization may have failed"
        if [ -n "$SUBMISSION_ID" ]; then
            echo "▸ Fetching notarization log..."
            xcrun notarytool log "$SUBMISSION_ID" \
                --apple-id "$APPLE_ID" \
                --team-id "$TEAM_ID" \
                --password "$APP_PASSWORD" \
                "$DIST_DIR/notarization-log.json" 2>/dev/null || true
            if [ -f "$DIST_DIR/notarization-log.json" ]; then
                echo "  → Log saved to dist/notarization-log.json"
                cat "$DIST_DIR/notarization-log.json"
            fi
        fi
        exit 1
    fi

    echo "▸ Stapling notarization ticket..."
    if [ -f "$DMG_PATH" ]; then
        xcrun stapler staple "$DMG_PATH"
    fi
    xcrun stapler staple "$APP_BUNDLE"

    # Verify notarization
    echo "▸ Verifying notarization..."
    spctl --assess --type execute --verbose=2 "$APP_BUNDLE" 2>&1 || true

    echo "✓ Notarization complete — app is ready for distribution"
    echo ""
fi

# ── Step 7: Distributable zip ────────────────────────
# Runs after signing and stapling so the notarization ticket travels with
# the archive. ditto preserves resource forks and extended attributes.
ZIP_PATH="$DIST_DIR/${APP_NAME}.zip"
if $DO_ZIP; then
    echo "▸ Creating distributable zip..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    echo "✓ Zip created: $ZIP_PATH"
    echo ""
fi

# ── Summary ───────────────────────────────────────────
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Done!"
echo ""
echo "  .app → $APP_BUNDLE ($APP_SIZE)"
if $DO_DMG && [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
    echo "  .dmg → $DMG_PATH ($DMG_SIZE)"
fi
if $DO_ZIP && [ -f "$ZIP_PATH" ]; then
    ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
    echo "  .zip → $ZIP_PATH ($ZIP_SIZE)"
fi
SIGN_TYPE="ad-hoc"
if $DO_SIGN; then SIGN_TYPE="Developer ID"; fi
echo "  sign → $SIGN_TYPE"
echo ""
echo "  To test: open \"$APP_BUNDLE\""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
