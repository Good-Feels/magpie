#!/usr/bin/env bash
set -euo pipefail

SCREENSHOT_DIR="docs/assets/screenshots"
MAX_WIDTH="${MAX_WIDTH:-900}"
WEBP_QUALITY="${WEBP_QUALITY:-78}"

if ! command -v cwebp >/dev/null 2>&1; then
  echo "cwebp not found. Install with: brew install webp"
  exit 1
fi

if [ ! -d "$SCREENSHOT_DIR" ]; then
  echo "Screenshot directory not found: $SCREENSHOT_DIR"
  exit 1
fi

echo "Optimizing screenshots in $SCREENSHOT_DIR"
echo "MAX_WIDTH=$MAX_WIDTH, WEBP_QUALITY=$WEBP_QUALITY"

for src in "$SCREENSHOT_DIR"/*.png "$SCREENSHOT_DIR"/*.jpg "$SCREENSHOT_DIR"/*.jpeg; do
  [ -f "$src" ] || continue

  base="${src%.*}"
  out="${base}.webp"

  width="$(sips -g pixelWidth "$src" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$src" 2>/dev/null | awk '/pixelHeight/ {print $2}')"

  if [ -z "${width:-}" ] || [ -z "${height:-}" ]; then
    echo "Skipping $src (unable to read dimensions)"
    continue
  fi

  ratio="$(awk -v w="$width" -v h="$height" 'BEGIN { printf "%.3f", w / h }')"

  resize_args=()
  if [ "$width" -gt "$MAX_WIDTH" ]; then
    resize_args=(-resize "$MAX_WIDTH" 0)
  fi

  cwebp -quiet -mt -af -m 6 -q "$WEBP_QUALITY" "${resize_args[@]}" "$src" -o "$out"

  png_bytes="$(wc -c < "$src" | tr -d ' ')"
  webp_bytes="$(wc -c < "$out" | tr -d ' ')"
  savings="$(awk -v p="$png_bytes" -v w="$webp_bytes" 'BEGIN { if (p==0) print "0.0"; else printf "%.1f", ((p-w)/p)*100 }')"

  printf "%s -> %s | %sx%s (ratio %s) | %s -> %s bytes (%s%% smaller)\n" \
    "$src" "$out" "$width" "$height" "$ratio" "$png_bytes" "$webp_bytes" "$savings"
done
