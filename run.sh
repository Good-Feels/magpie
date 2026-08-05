#!/bin/bash
# Build and run Magpie as a proper macOS .app bundle.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/Magpie.app"
ICON_ICNS="$PROJECT_DIR/Magpie/Resources/AppIcon.icns"
ASSETS_CAR="$PROJECT_DIR/Magpie/Resources/Assets.car"
INFO_PLIST="$PROJECT_DIR/Magpie/Info.plist"
KEEPER_PLIST="$PROJECT_DIR/Support/com.goodfeels.magpie.keeper.plist"
DEV_KEEPER_PLIST_NAME="com.goodfeels.magpie.dev.keeper.plist"

echo "Building Magpie..."
cd "$PROJECT_DIR"
swift build 2>&1

echo "Generating app icon..."
"$PROJECT_DIR/scripts/generate-app-icon.sh" "$PROJECT_DIR/app-icon.png" "$PROJECT_DIR/Magpie/Resources"

echo "Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"
rm -rf "$APP_BUNDLE/Contents/Library/LaunchAgents" "$APP_BUNDLE/Contents/Library/LaunchServices"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchAgents"
mkdir -p "$APP_BUNDLE/Contents/Library/LaunchServices"
cp -f .build/debug/Magpie "$APP_BUNDLE/Contents/MacOS/Magpie"
cp -f .build/debug/MagpieKeeper "$APP_BUNDLE/Contents/Library/LaunchServices/MagpieKeeper"
cp -f "$KEEPER_PLIST" "$APP_BUNDLE/Contents/Library/LaunchAgents/$DEV_KEEPER_PLIST_NAME"
cp -f "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"

# Give the dev build its own bundle ID. A second copy of
# com.goodfeels.magpie on disk makes LaunchServices/Background Task
# Management resolve the login item to the wrong (stale) bundle, which
# breaks launch-at-login for the installed app.
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.goodfeels.magpie.dev" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :Label com.goodfeels.magpie.dev.keeper" \
    "$APP_BUNDLE/Contents/Library/LaunchAgents/$DEV_KEEPER_PLIST_NAME"
cp -f "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if [ -f "$ASSETS_CAR" ]; then
    cp -f "$ASSETS_CAR" "$APP_BUNDLE/Contents/Resources/Assets.car"
fi

# Add rpath so the binary finds frameworks in Contents/Frameworks
install_name_tool -add_rpath @loader_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Magpie" 2>/dev/null || true

# Copy Sparkle framework (dynamic library, must be bundled)
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -Rf "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
fi

# Code-sign so macOS recognises the app for privacy prompts (clipboard, etc.)
REQUESTED_SIGN_IDENTITY="${MAGPIE_SIGN_IDENTITY:-Apple Development}"
if security find-identity -v -p codesigning | grep -Fq "$REQUESTED_SIGN_IDENTITY"; then
    CODE_SIGN_IDENTITY="$REQUESTED_SIGN_IDENTITY"
    echo "Signing with $CODE_SIGN_IDENTITY..."
else
    CODE_SIGN_IDENTITY="-"
    echo "No valid '$REQUESTED_SIGN_IDENTITY' identity found; signing ad hoc for local use..."
fi

EMBEDDED_SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
if [ -d "$EMBEDDED_SPARKLE_FW" ]; then
    EMBEDDED_SPARKLE_CURRENT="$(cd "$EMBEDDED_SPARKLE_FW/Versions/Current" && pwd)"

    if [ -d "$EMBEDDED_SPARKLE_CURRENT/XPCServices/Installer.xpc" ]; then
        codesign --force --sign "$CODE_SIGN_IDENTITY" \
            "$EMBEDDED_SPARKLE_CURRENT/XPCServices/Installer.xpc"
    fi

    if [ -d "$EMBEDDED_SPARKLE_CURRENT/XPCServices/Downloader.xpc" ]; then
        codesign --force --sign "$CODE_SIGN_IDENTITY" \
            --preserve-metadata=entitlements \
            "$EMBEDDED_SPARKLE_CURRENT/XPCServices/Downloader.xpc"
    fi

    if [ -f "$EMBEDDED_SPARKLE_CURRENT/Autoupdate" ]; then
        codesign --force --sign "$CODE_SIGN_IDENTITY" \
            "$EMBEDDED_SPARKLE_CURRENT/Autoupdate"
    fi

    if [ -d "$EMBEDDED_SPARKLE_CURRENT/Updater.app" ]; then
        codesign --force --sign "$CODE_SIGN_IDENTITY" \
            "$EMBEDDED_SPARKLE_CURRENT/Updater.app"
    fi

    codesign --force --sign "$CODE_SIGN_IDENTITY" "$EMBEDDED_SPARKLE_FW"
fi

codesign --force --sign "$CODE_SIGN_IDENTITY" \
    "$APP_BUNDLE/Contents/Library/LaunchServices/MagpieKeeper"
codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"

# Stop only this workspace's development copy, never the installed app.
pkill -f "^$APP_BUNDLE/Contents/MacOS/Magpie$" 2>/dev/null && sleep 0.5 || true

echo "Launching Magpie..."
open "$APP_BUNDLE"
echo "Running! Look for the clipboard icon in your menu bar."
