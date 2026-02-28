#!/bin/bash
# Build and run Magpie as a proper macOS .app bundle.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/Magpie.app"

echo "Building Magpie..."
cd "$PROJECT_DIR"
swift build 2>&1

echo "Assembling .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp -f .build/debug/Magpie "$APP_BUNDLE/Contents/MacOS/Magpie"

# Kill any existing instance
killall Magpie 2>/dev/null && sleep 0.5 || true

echo "Launching Magpie..."
open "$APP_BUNDLE"
echo "Running! Look for the clipboard icon in your menu bar."
