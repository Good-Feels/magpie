#!/bin/bash
# Build and run Magpie as a proper macOS .app bundle.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/Magpie.app"
ICON_ICNS="$PROJECT_DIR/Magpie/Resources/AppIcon.icns"
ASSETS_CAR="$PROJECT_DIR/Magpie/Resources/Assets.car"
INFO_PLIST="$PROJECT_DIR/Magpie/Info.plist"

echo "Building Magpie..."
cd "$PROJECT_DIR"
swift build 2>&1

echo "Generating app icon..."
"$PROJECT_DIR/scripts/generate-app-icon.sh" "$PROJECT_DIR/app-icon.png" "$PROJECT_DIR/Magpie/Resources"

echo "Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp -f .build/debug/Magpie "$APP_BUNDLE/Contents/MacOS/Magpie"
cp -f "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
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
echo "Signing..."
codesign --force --deep --sign "Apple Development" "$APP_BUNDLE"

# Kill any existing instance
killall Magpie 2>/dev/null && sleep 0.5 || true

echo "Launching Magpie..."
open "$APP_BUNDLE"
echo "Running! Look for the clipboard icon in your menu bar."
