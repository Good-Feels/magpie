#!/bin/bash
#
# build-release.sh — Build a signed/notarized distributable Magpie.app + DMG
#
# Examples:
#   ./scripts/build-release.sh \
#     --sign-identity "Developer ID Application: Good Feels (HTPHAYLD9X)"
#
#   ./scripts/build-release.sh \
#     --sign-identity "Developer ID Application: Good Feels (HTPHAYLD9X)" \
#     --notarize --keychain-profile "AC_NOTARY"
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Magpie.app"
DMG_PATH="$DIST_DIR/Magpie.dmg"
RW_DMG_PATH="$DIST_DIR/Magpie-rw.dmg"
MOUNT_DIR="$DIST_DIR/.dmg-mount"
INFO_PLIST="$PROJECT_DIR/Magpie/Info.plist"
ENTITLEMENTS_FILE="$PROJECT_DIR/Magpie/Magpie.entitlements"
ICON_SOURCE="$PROJECT_DIR/app-icon.png"
ICON_ICNS="$PROJECT_DIR/Magpie/Resources/AppIcon.icns"
ASSETS_CAR="$PROJECT_DIR/Magpie/Resources/Assets.car"
DMG_BG_IMAGE="$DIST_DIR/.dmg-background.png"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

SIGN_IDENTITY=""
ALLOW_UNSIGNED=false
NOTARIZE=false
KEYCHAIN_PROFILE=""
APPLE_ID=""
TEAM_ID=""
APP_PASSWORD=""
FANCY_DMG=true
RELEASE_TAG=""
REPO_SLUG=""
UPDATE_APPCAST=true

usage() {
    cat <<'EOF'
Usage:
  ./scripts/build-release.sh [options]

Options:
  --sign-identity <name>      Signing identity, e.g. "Developer ID Application: ...".
  --allow-unsigned            Build unsigned DMG (for internal testing only).
  --notarize                  Notarize DMG after signing.
  --keychain-profile <name>   notarytool keychain profile (recommended for notarization).
  --apple-id <email>          Apple ID (fallback notarization auth).
  --team-id <id>              Apple team ID (fallback notarization auth).
  --app-password <password>   App-specific password (fallback notarization auth).
  --no-fancy-dmg              Build a plain DMG without custom background/layout.
  --tag <tag>                 Release tag used for appcast URL (for example v1.0.0).
  --repo <owner/repo>         GitHub slug used for appcast URL (auto-detected if omitted).
  --skip-appcast              Skip appcast update/signing.
  --help                      Show this help text.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign-identity)
            SIGN_IDENTITY="$2"
            shift 2
            ;;
        --allow-unsigned)
            ALLOW_UNSIGNED=true
            shift
            ;;
        --notarize)
            NOTARIZE=true
            shift
            ;;
        --keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
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
        --no-fancy-dmg)
            FANCY_DMG=false
            shift
            ;;
        --tag)
            RELEASE_TAG="$2"
            shift 2
            ;;
        --repo)
            REPO_SLUG="$2"
            shift 2
            ;;
        --skip-appcast)
            UPDATE_APPCAST=false
            shift
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

if [[ -z "$SIGN_IDENTITY" && "$ALLOW_UNSIGNED" != true ]]; then
    echo "ERROR: --sign-identity is required for release builds."
    echo "Use --allow-unsigned only for local/internal testing."
    exit 1
fi

if [[ "$NOTARIZE" == true && -z "$SIGN_IDENTITY" ]]; then
    echo "ERROR: Notarization requires a signed build."
    exit 1
fi

if [[ "$NOTARIZE" == true && -z "$KEYCHAIN_PROFILE" ]]; then
    if [[ -z "$APPLE_ID" || -z "$TEAM_ID" || -z "$APP_PASSWORD" ]]; then
        echo "ERROR: Notarization requires either:"
        echo "  1) --keychain-profile <profile>"
        echo "  2) --apple-id + --team-id + --app-password"
        exit 1
    fi
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "ERROR: Info.plist not found at $INFO_PLIST"
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
    echo "ERROR: Entitlements file not found at $ENTITLEMENTS_FILE"
    exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "ERROR: Source icon not found at $ICON_SOURCE"
    exit 1
fi

if ! /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST" >/dev/null 2>&1; then
    if [[ "$ALLOW_UNSIGNED" == true ]]; then
        echo "WARNING: SUPublicEDKey is missing from Info.plist."
        echo "         Sparkle update signatures are not pinned yet."
        echo "         Add SUPublicEDKey before publishing auto-updates."
    else
        echo "ERROR: SUPublicEDKey is missing from Info.plist."
        echo "       Add Sparkle public key before shipping a release."
        exit 1
    fi
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")"

echo "==> Cleaning dist..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Building release binary..."
cd "$PROJECT_DIR"
swift build -c release

echo "==> Generating app icon..."
"$PROJECT_DIR/scripts/generate-app-icon.sh" "$ICON_SOURCE" "$PROJECT_DIR/Magpie/Resources"

echo "==> Assembling app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Frameworks" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/Magpie" "$APP_BUNDLE/Contents/MacOS/Magpie"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
if [[ -f "$ASSETS_CAR" ]]; then
    cp "$ASSETS_CAR" "$APP_BUNDLE/Contents/Resources/Assets.car"
fi
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

install_name_tool -add_rpath @loader_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Magpie" 2>/dev/null || true

SPARKLE_FW="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    cp -Rf "$SPARKLE_FW" "$APP_BUNDLE/Contents/Frameworks/"
fi

echo "==> Stripping binary..."
strip -x "$APP_BUNDLE/Contents/MacOS/Magpie" 2>/dev/null || true

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing app with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS_FILE" \
        "$APP_BUNDLE"

    echo "==> Verifying app signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
    spctl --assess --type execute --verbose "$APP_BUNDLE" || true
else
    echo "==> Skipping signing (unsigned test build)"
fi

echo "==> Creating DMG..."
hdiutil create -size 220m -fs HFS+ -volname "Magpie" -ov "$RW_DMG_PATH"

rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"
MOUNT_OUTPUT="$(hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR")"
DEVICE="$(echo "$MOUNT_OUTPUT" | awk '{print $1; exit}')"
VOLUME_PATH="$MOUNT_DIR"

cp -R "$APP_BUNDLE" "$VOLUME_PATH/"
ln -snf /Applications "$VOLUME_PATH/Applications"

if [[ "$FANCY_DMG" == true ]]; then
    echo "==> Styling DMG window..."
    "$PROJECT_DIR/scripts/generate-dmg-background.sh" "$DMG_BG_IMAGE" "$ICON_SOURCE" || true
    mkdir -p "$VOLUME_PATH/.background"
    cp -f "$DMG_BG_IMAGE" "$VOLUME_PATH/.background/background.png" || true

    set +e
    osascript - "$VOLUME_PATH" <<'APPLESCRIPT'
on run argv
set mountPath to item 1 of argv
tell application "Finder"
    activate
    set dmgFolder to POSIX file mountPath as alias
    open dmgFolder
    set dmgWindow to front Finder window
    delay 0.4
    try
        set current view of dmgWindow to icon view
    end try
    delay 0.2
    try
        set toolbar visible of dmgWindow to false
    end try
    try
        set statusbar visible of dmgWindow to false
    end try
    try
        set the bounds of dmgWindow to {120, 120, 800, 540}
    end try
    set viewOptions to missing value
    try
        set viewOptions to the icon view options of dmgWindow
    on error
        delay 0.4
        try
            set current view of dmgWindow to icon view
            set viewOptions to the icon view options of dmgWindow
        end try
    end try
    if viewOptions is not missing value then
        try
            set arrangement of viewOptions to not arranged
        end try
        try
            set icon size of viewOptions to 116
        end try
        try
            set text size of viewOptions to 14
        end try
        try
            set background picture of viewOptions to file ".background:background.png" of dmgWindow
        end try
    end if
    try
        set position of item "Magpie.app" of dmgWindow to {170, 245}
    end try
    try
        set position of item "Applications" of dmgWindow to {510, 245}
    end try
    close dmgWindow
    delay 0.4
end tell
end run
APPLESCRIPT
    SCRIPT_EXIT=$?
    set -e

    if [[ $SCRIPT_EXIT -ne 0 ]]; then
        echo "WARNING: Could not apply Finder-based DMG layout. Continuing with plain layout."
    fi
fi

sync
hdiutil detach "$DEVICE" -quiet
rmdir "$MOUNT_DIR" 2>/dev/null || true

hdiutil convert "$RW_DMG_PATH" -ov -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
fi

if [[ "$NOTARIZE" == true ]]; then
    echo "==> Notarizing DMG..."
    if [[ -n "$KEYCHAIN_PROFILE" ]]; then
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    else
        xcrun notarytool submit "$DMG_PATH" \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$APP_PASSWORD" \
            --wait
    fi

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "$DMG_PATH"
fi

echo "==> Final artifact checks..."
spctl --assess --type open --verbose "$DMG_PATH" || true
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

if [[ "$UPDATE_APPCAST" == true ]]; then
    if [[ -z "$RELEASE_TAG" ]]; then
        echo "ERROR: --tag is required when appcast updates are enabled."
        echo "       Pass --tag vX.Y.Z or use --skip-appcast."
        exit 1
    fi

    echo "==> Updating and signing appcast..."
    APPCAST_ARGS=(--tag "$RELEASE_TAG" --dmg "$DMG_PATH" --appcast "$APPCAST_PATH" --info-plist "$INFO_PLIST")
    if [[ -n "$REPO_SLUG" ]]; then
        APPCAST_ARGS+=(--repo "$REPO_SLUG")
    fi
    "$PROJECT_DIR/scripts/update-appcast.sh" "${APPCAST_ARGS[@]}"
fi

echo
echo "============================================"
echo "  Magpie release build complete"
echo "============================================"
echo "Version:       $VERSION ($BUILD_NUMBER)"
echo "App:           $APP_BUNDLE"
echo "DMG:           $DMG_PATH"
echo "SHA256 file:   $DMG_PATH.sha256"
echo "Signed:        $([[ -n "$SIGN_IDENTITY" ]] && echo YES || echo NO)"
echo "Notarized:     $([[ "$NOTARIZE" == true ]] && echo YES || echo NO)"
echo "Appcast:       $([[ "$UPDATE_APPCAST" == true ]] && echo UPDATED || echo SKIPPED)"
echo
echo "Next: upload DMG + SHA256 to GitHub Release."
echo "      Commit appcast.xml if this build generated a new entry."
