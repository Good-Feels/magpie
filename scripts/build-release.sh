#!/bin/bash
#
# build-release.sh — Build a distributable Magpie.app
#
# Usage:
#   ./scripts/build-release.sh                    # Unsigned build
#   ./scripts/build-release.sh --sign "Developer ID Application: Your Name (TEAMID)"
#   ./scripts/build-release.sh --sign "Developer ID Application: Your Name (TEAMID)" --notarize
#
# Outputs:
#   dist/Magpie.dmg       — Drag-to-install disk image
#   dist/Magpie.app       — The signed .app bundle
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Magpie.app"
DMG_PATH="$DIST_DIR/Magpie.dmg"
DMG_TEMP="$DIST_DIR/dmg-staging"

SIGN_IDENTITY=""
NOTARIZE=false
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""

# ── Parse Arguments ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        --team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        --app-password)
            APP_PASSWORD="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ── Clean ────────────────────────────────────────────────────────────
echo "==> Cleaning previous build..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ── Build (Release) ─────────────────────────────────────────────────
echo "==> Building Magpie in release mode..."
cd "$PROJECT_DIR"
swift build -c release 2>&1

# ── Assemble .app Bundle ────────────────────────────────────────────
echo "==> Assembling Magpie.app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the release binary
cp "$BUILD_DIR/Magpie" "$APP_BUNDLE/Contents/MacOS/Magpie"

# Copy Info.plist
cp "$PROJECT_DIR/Magpie.app/Contents/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Create a minimal PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ── Strip Debug Symbols ─────────────────────────────────────────────
echo "==> Stripping debug symbols..."
strip -x "$APP_BUNDLE/Contents/MacOS/Magpie" 2>/dev/null || true

# ── Code Sign ────────────────────────────────────────────────────────
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Code signing with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" \
        --entitlements /dev/stdin \
        "$APP_BUNDLE" <<'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

    echo "==> Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "    Signature OK"
else
    echo "==> Skipping code signing (no --sign provided)"
    echo "    Users will need to right-click > Open on first launch"
fi

# ── Create DMG ───────────────────────────────────────────────────────
echo "==> Creating DMG..."
mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create a symlink to /Applications for drag-to-install
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "Magpie" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1

rm -rf "$DMG_TEMP"

# ── Notarize ─────────────────────────────────────────────────────────
if [[ "$NOTARIZE" == true ]]; then
    if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
        echo "==> Notarization requires --apple-id, --team-id, and --app-password"
        echo "    Generate an app-specific password at https://appleid.apple.com"
        echo ""
        echo "    Example:"
        echo "    ./scripts/build-release.sh \\"
        echo "      --sign \"Developer ID Application: ...\" \\"
        echo "      --notarize \\"
        echo "      --apple-id you@example.com \\"
        echo "      --team-id ABCDEF1234 \\"
        echo "      --app-password xxxx-xxxx-xxxx-xxxx"
        exit 1
    fi

    echo "==> Submitting for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_PASSWORD" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Magpie build complete!"
echo "============================================"
echo ""
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "  Size: $DMG_SIZE"
echo ""
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "  Signed: YES"
    if [[ "$NOTARIZE" == true ]]; then
        echo "  Notarized: YES"
    else
        echo "  Notarized: NO (run with --notarize to notarize)"
    fi
else
    echo "  Signed: NO (unsigned — users right-click > Open)"
fi
echo ""
echo "  Upload the DMG to GitHub Releases!"
echo ""
