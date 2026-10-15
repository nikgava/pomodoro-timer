#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="release"

case "${1:-}" in
    "") ;;
    --debug) CONFIGURATION="debug" ;;
    *) printf 'Usage: %s [--debug]\n' "$0" >&2; exit 2 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [--debug]\n' "$0" >&2
    exit 2
fi

cd "$PROJECT_ROOT"
swift build --configuration "$CONFIGURATION" --arch arm64
BIN_DIRECTORY="$(swift build --configuration "$CONFIGURATION" --arch arm64 --show-bin-path)"
DIST_PATH="$PROJECT_ROOT/dist"
APP_PATH="$DIST_PATH/Pomodoro.app"
mkdir -p "$DIST_PATH"
POMODORO_STAGING_DIR="$(mktemp -d "$DIST_PATH/.pomodoro-build.XXXXXX")"
trap 'rm -rf "$POMODORO_STAGING_DIR"' EXIT
STAGED_APP_PATH="$POMODORO_STAGING_DIR/Pomodoro.app"

mkdir -p "$STAGED_APP_PATH/Contents/MacOS" "$STAGED_APP_PATH/Contents/Resources"
cp "$BIN_DIRECTORY/Pomodoro" "$STAGED_APP_PATH/Contents/MacOS/Pomodoro"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP_PATH/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$STAGED_APP_PATH/Contents/Resources/AppIcon.icns"
chmod 755 "$STAGED_APP_PATH/Contents/MacOS/Pomodoro"
plutil -lint "$STAGED_APP_PATH/Contents/Info.plist"

# A local signature permits launch without requiring a paid developer account.
# Set CODE_SIGN_IDENTITY to an installed Developer ID identity for distribution.
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp=none "$STAGED_APP_PATH"
codesign --verify --strict "$STAGED_APP_PATH"

ARCHIVE_PATH="$DIST_PATH/Pomodoro-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP_PATH" "$POMODORO_STAGING_DIR/Pomodoro-macOS-arm64.zip"

# Preserve the previous bundle and its executable inode if the app is running.
if [[ -e "$APP_PATH" || -L "$APP_PATH" ]]; then
    mkdir -p "$DIST_PATH/.previous"
    PREVIOUS_APP_PATH="$DIST_PATH/.previous/Pomodoro.app"
    if [[ -e "$PREVIOUS_APP_PATH" || -L "$PREVIOUS_APP_PATH" ]]; then
        POMODORO_PREVIOUS_DIR="$(mktemp -d "$DIST_PATH/.previous/build.XXXXXX")"
        PREVIOUS_APP_PATH="$POMODORO_PREVIOUS_DIR/Pomodoro.app"
    fi
    mv "$APP_PATH" "$PREVIOUS_APP_PATH"
    printf 'Previous app preserved: %s\n' "$PREVIOUS_APP_PATH"
fi
mv "$STAGED_APP_PATH" "$APP_PATH"
mv -f "$POMODORO_STAGING_DIR/Pomodoro-macOS-arm64.zip" "$ARCHIVE_PATH"
printf '\nApp: %s\nArchive: %s\n' "$APP_PATH" "$ARCHIVE_PATH"
