#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"
INFO_PLIST="$PROJECT_DIR/Magpie/Info.plist"
DMG_PATH="$PROJECT_DIR/dist/Magpie.dmg"
TAG=""
REPO_SLUG=""
SPARKLE_ACCOUNT="ed25519"

usage() {
    cat <<'EOF'
Usage:
  ./scripts/update-appcast.sh --tag <tag> [options]

Options:
  --tag <tag>               GitHub release tag (for example v1.0.0). Required.
  --repo <owner/repo>       GitHub repo slug. Auto-detected from git remote if omitted.
  --dmg <path>              DMG file path. Default: dist/Magpie.dmg
  --appcast <path>          appcast.xml path. Default: ./appcast.xml
  --info-plist <path>       Info.plist path. Default: Magpie/Info.plist
  --sparkle-account <name>  Sparkle key account name (default: ed25519)
  --help                    Show help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --repo)
            REPO_SLUG="$2"
            shift 2
            ;;
        --dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        --appcast)
            APPCAST_PATH="$2"
            shift 2
            ;;
        --info-plist)
            INFO_PLIST="$2"
            shift 2
            ;;
        --sparkle-account)
            SPARKLE_ACCOUNT="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$TAG" ]]; then
    echo "ERROR: --tag is required."
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    exit 1
fi

if [[ ! -f "$APPCAST_PATH" ]]; then
    echo "ERROR: appcast not found at $APPCAST_PATH"
    exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Info.plist not found at $INFO_PLIST"
    exit 1
fi

if [[ -z "$REPO_SLUG" ]]; then
    ORIGIN_URL="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
    if [[ "$ORIGIN_URL" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
        REPO_SLUG="${BASH_REMATCH[1]}"
    fi
fi

if [[ -z "$REPO_SLUG" ]]; then
    echo "ERROR: Could not determine GitHub repo slug. Pass --repo owner/repo."
    exit 1
fi

SPARKLE_SIGN="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$SPARKLE_SIGN" ]]; then
    echo "ERROR: Sparkle sign_update tool not found at $SPARKLE_SIGN"
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || true)"
DMG_NAME="$(basename "$DMG_PATH")"
DMG_SIZE="$(stat -f%z "$DMG_PATH")"
DMG_URL="https://github.com/$REPO_SLUG/releases/download/$TAG/$DMG_NAME"
PUB_DATE="$(LC_ALL=C date -Ru)"
ED_SIGNATURE="$("$SPARKLE_SIGN" --account "$SPARKLE_ACCOUNT" -p "$DMG_PATH")"

if grep -q "$DMG_URL" "$APPCAST_PATH"; then
    echo "ERROR: appcast already contains an item for $DMG_URL"
    exit 1
fi

ITEM_FILE="$(mktemp)"
cat > "$ITEM_FILE" <<EOF
        <item>
            <title>Magpie ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
$( [[ -n "$MIN_SYSTEM" ]] && printf "            <sparkle:minimumSystemVersion>%s</sparkle:minimumSystemVersion>\n" "$MIN_SYSTEM" )
            <enclosure url="${DMG_URL}" length="${DMG_SIZE}" type="application/x-apple-diskimage" sparkle:edSignature="${ED_SIGNATURE}" />
        </item>
EOF

TMP_APPCAST="$(mktemp)"
awk -v itemFile="$ITEM_FILE" '
    /<\/channel>/ {
        while ((getline line < itemFile) > 0) print line
        close(itemFile)
    }
    { print }
' "$APPCAST_PATH" > "$TMP_APPCAST"
mv "$TMP_APPCAST" "$APPCAST_PATH"
rm -f "$ITEM_FILE"

"$SPARKLE_SIGN" --account "$SPARKLE_ACCOUNT" "$APPCAST_PATH" >/dev/null

echo "Updated and signed appcast: $APPCAST_PATH"
echo "Added item URL: $DMG_URL"
