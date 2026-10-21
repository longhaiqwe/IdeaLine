#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ "${IDEALINE_DISTRIBUTION:-0}" == 1 ]]; then
  if [[ "${IDEALINE_CODE_SIGN_IDENTITY:-}" != "Developer ID Application: "* ]]; then
    echo 'Distribution requires IDEALINE_CODE_SIGN_IDENTITY (Developer ID Application).' >&2
    exit 2
  fi
  python3 scripts/release_config.py --require-updates "$WORK/Info.plist"
else
  python3 scripts/release_config.py "$WORK/Info.plist"
fi
BUILD_ARGS=(-c release)
if [[ "${IDEALINE_UNIVERSAL:-0}" == 1 ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
DESTINATION="${IDEALINE_OUTPUT_DIR:-build}"
APP="$WORK/灵感晾台.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_PATH/IdeaLine" "$APP/Contents/MacOS/IdeaLine"
SPARKLE_ROOT=".build/artifacts/sparkle/Sparkle"
ditto "$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$WORK/Info.plist" "$APP/Contents/Info.plist"
swift scripts/make-icon.swift "$WORK/icon.png"
mkdir -p "$WORK/IdeaLine.iconset"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$WORK/icon.png" --out "$WORK/IdeaLine.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z "$((s*2))" "$((s*2))" "$WORK/icon.png" --out "$WORK/IdeaLine.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/IdeaLine.iconset" -o "$APP/Contents/Resources/IdeaLine.icns"
cp THIRD_PARTY_LICENSES.txt "$APP/Contents/Resources/"
cp "$SPARKLE_ROOT/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
IDENTITY="${IDEALINE_CODE_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$FRAMEWORK/Versions/Current"
# Sign inside out. Preserve the downloader's sandbox entitlements.
codesign "${SIGN_ARGS[@]}" "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign "${SIGN_ARGS[@]}" --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign "${SIGN_ARGS[@]}" "$SPARKLE_VERSION/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE_VERSION/Updater.app"
codesign "${SIGN_ARGS[@]}" "$FRAMEWORK"
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
mkdir -p "$DESTINATION"
# Only replace the generated bundle after the complete staged build verifies.
if [[ -e "$DESTINATION/灵感晾台.app" ]]; then
  mv "$DESTINATION/灵感晾台.app" "$DESTINATION/灵感晾台.previous.$(date +%s).app"
fi
ditto "$APP" "$DESTINATION/灵感晾台.app"
printf 'Built: %s/灵感晾台.app\n' "$DESTINATION"
