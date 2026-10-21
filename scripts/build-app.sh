#!/usr/bin/env bash
# Builds build/cLockIn.app and signs it.
# Signs with the "NotAdep Code Signing" certificate when it's in the keychain, otherwise ad hoc.
# Override with CODESIGN_IDENTITY="<name>" or CONFIG=debug.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:-NotAdep Code Signing}"
APP="build/cLockIn.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/cLockIn" "$APP/Contents/MacOS/cLockIn"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "Signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "Signed ad hoc (\"$IDENTITY\" not found)"
fi
echo "Built $APP"
