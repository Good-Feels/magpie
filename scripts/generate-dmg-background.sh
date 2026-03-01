#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PATH="${1:-$PROJECT_DIR/dist/.dmg-background.png}"
ICON_PATH="${2:-$PROJECT_DIR/app-icon.png}"

mkdir -p "$(dirname "$OUT_PATH")"

python3 - "$OUT_PATH" "$ICON_PATH" <<'PY'
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

out_path = sys.argv[1]

w, h = 680, 420
img = Image.new("RGBA", (w, h), (16, 21, 48, 255))
draw = ImageDraw.Draw(img)

# Vertical gradient background
top = (106, 131, 255)
bottom = (20, 29, 80)
for y in range(h):
    t = y / max(1, h - 1)
    r = int(top[0] * (1 - t) + bottom[0] * t)
    g = int(top[1] * (1 - t) + bottom[1] * t)
    b = int(top[2] * (1 - t) + bottom[2] * t)
    draw.line((0, y, w, y), fill=(r, g, b, 255))

# Soft ambient glow
glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
gdraw = ImageDraw.Draw(glow)
gdraw.ellipse((80, 20, 600, 360), fill=(180, 200, 255, 82))
glow = glow.filter(ImageFilter.GaussianBlur(40))
img = Image.alpha_composite(img, glow)
draw = ImageDraw.Draw(img)

# Panels behind icons
panel_color = (255, 255, 255, 244)
outline = (255, 255, 255, 255)
draw.rounded_rectangle((88, 136, 258, 306), radius=26, fill=panel_color, outline=outline, width=1)
draw.rounded_rectangle((422, 136, 592, 306), radius=26, fill=panel_color, outline=outline, width=1)

# Arrow path
path = [(280, 220), (350, 220), (350, 205), (398, 235), (350, 265), (350, 250), (280, 250)]
draw.polygon(path, fill=(255, 255, 255, 214))

# Load font
font = ImageFont.load_default()
try:
    for candidate in [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    ]:
        if os.path.exists(candidate):
            font = ImageFont.truetype(candidate, 34)
            break
except Exception:
    font = ImageFont.load_default()

subtitle_font = ImageFont.load_default()
try:
    for candidate in [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
    ]:
        if os.path.exists(candidate):
            subtitle_font = ImageFont.truetype(candidate, 18)
            break
except Exception:
    subtitle_font = ImageFont.load_default()

title = "Drag Magpie to Applications"
bbox = draw.textbbox((0, 0), title, font=font)
tw = bbox[2] - bbox[0]
draw.text(((w - tw) // 2, 44), title, font=font, fill=(255, 255, 255, 242))

subtitle = "Install once. Launch from Applications."
sb = draw.textbbox((0, 0), subtitle, font=subtitle_font)
sw = sb[2] - sb[0]
draw.text(((w - sw) // 2, 92), subtitle, font=subtitle_font, fill=(245, 247, 255, 225))

img.save(out_path, format="PNG")
print(f"Generated DMG background: {out_path}")
PY
