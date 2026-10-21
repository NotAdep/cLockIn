#!/usr/bin/env bash
# Builds build/cLockIn.app and signs it.
# Signs with the "NotAdep Code Signing" certificate when it's in the keychain, otherwise ad hoc.
# Override with CODESIGN_IDENTITY="<name>" or CONFIG=debug.
# PROBE=1 adds the debug-only tooling (snapshots, animation probe) to an optimized build.
# UNIVERSAL=1 builds for both Apple silicon and Intel. VERSION=1.2.3 stamps that version into the app.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:-NotAdep Code Signing}"
APP="build/cLockIn.app"

FLAGS=()
if [[ "${PROBE:-0}" == "1" ]]; then FLAGS+=(-Xswiftc -DDEBUG); fi
if [[ "${UNIVERSAL:-0}" == "1" ]]; then FLAGS+=(--arch arm64 --arch x86_64); fi
swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${FLAGS[@]+"${FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/cLockIn" "$APP/Contents/MacOS/cLockIn"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${VERSION:-}" ]]; then
  BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
  echo "Signed ad hoc"
elif security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (\"$IDENTITY\" not found)"
fi
echo "Built $APP"
