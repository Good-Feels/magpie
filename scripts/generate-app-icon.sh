#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="${1:-$PROJECT_DIR/app-icon.png}"
OUT_DIR="${2:-$PROJECT_DIR/Magpie/Resources}"
TMP_DIR="$OUT_DIR/.icon-build"
ICONSET_DIR="$TMP_DIR/Assets.xcassets/AppIcon.appiconset"
BUILD_DIR="$TMP_DIR/build"
ACTOOL_LOG="$TMP_DIR/actool.log"

if [[ ! -f "$SOURCE_ICON" ]]; then
    echo "ERROR: Source icon not found: $SOURCE_ICON"
    exit 1
fi

# Asset compilation is expensive and depends on Xcode plug-ins. Reuse the
# checked build outputs when the source artwork has not changed.
if [[ -f "$OUT_DIR/AppIcon.icns" && -f "$OUT_DIR/Assets.car" && \
      "$OUT_DIR/AppIcon.icns" -nt "$SOURCE_ICON" && \
      "$OUT_DIR/Assets.car" -nt "$SOURCE_ICON" ]]; then
    rm -rf "$TMP_DIR"
    echo "App icon assets are up to date."
    exit 0
fi

PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! "$PYTHON_BIN" -c 'from PIL import Image, ImageChops, ImageDraw' >/dev/null 2>&1; then
    PYTHON_BIN=""
    for candidate in \
        /opt/homebrew/anaconda3/bin/python3 \
        /opt/homebrew/bin/python3 \
        /usr/local/bin/python3 \
        /usr/bin/python3; do
        if [[ -x "$candidate" ]] && \
            "$candidate" -c 'from PIL import Image, ImageChops, ImageDraw' >/dev/null 2>&1; then
            PYTHON_BIN="$candidate"
            break
        fi
    done
fi

if [[ -z "$PYTHON_BIN" ]]; then
    echo "ERROR: A native Python 3 installation with Pillow is required to generate the app icon."
    exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$ICONSET_DIR" "$BUILD_DIR"
rm -rf "$OUT_DIR/AppIcon.iconset"

"$PYTHON_BIN" - "$SOURCE_ICON" "$ICONSET_DIR" <<'PY'
import json
import os
import sys
from PIL import Image, ImageChops, ImageDraw

src = sys.argv[1]
out = sys.argv[2]
img = Image.open(src).convert("RGBA")
w, h = img.size

# Apply a rounded-corner mask so opaque source corners don't show in the final app icon.
corner_radius = int(min(w, h) * 0.22)
mask = Image.new("L", (w, h), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=corner_radius, fill=255)
alpha = img.getchannel("A")
img.putalpha(ImageChops.multiply(alpha, mask))

entries = [
    (16, "1x", "icon_16x16.png"),
    (16, "2x", "icon_16x16@2x.png"),
    (32, "1x", "icon_32x32.png"),
    (32, "2x", "icon_32x32@2x.png"),
    (128, "1x", "icon_128x128.png"),
    (128, "2x", "icon_128x128@2x.png"),
    (256, "1x", "icon_256x256.png"),
    (256, "2x", "icon_256x256@2x.png"),
    (512, "1x", "icon_512x512.png"),
    (512, "2x", "icon_512x512@2x.png"),
]

images = []
for base, scale, name in entries:
    px = base * (2 if scale == "2x" else 1)
    resized = img.resize((px, px), Image.Resampling.LANCZOS)
    resized.save(os.path.join(out, name), format="PNG")
    images.append({
        "idiom": "mac",
        "size": f"{base}x{base}",
        "scale": scale,
        "filename": name
    })

with open(os.path.join(out, "Contents.json"), "w", encoding="utf-8") as f:
    json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f)
PY

if ! xcrun actool \
    --compile "$BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/asset-info.plist" \
    "$TMP_DIR/Assets.xcassets" >"$ACTOOL_LOG" 2>&1; then
    cat "$ACTOOL_LOG"
    exit 1
fi

cp -f "$BUILD_DIR/AppIcon.icns" "$OUT_DIR/AppIcon.icns"
if [[ -f "$BUILD_DIR/Assets.car" ]]; then
    cp -f "$BUILD_DIR/Assets.car" "$OUT_DIR/Assets.car"
fi

rm -rf "$TMP_DIR"
echo "Generated: $OUT_DIR/AppIcon.icns"
