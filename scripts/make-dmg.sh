#!/usr/bin/env bash
# Builds a universal, ad hoc signed cLockIn.app and packs it into dist/cLockIn-<version>.dmg,
# with an Applications shortcut so it can be dragged straight in.
# The version comes from Resources/Info.plist unless VERSION is set (the release workflow passes the tag).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
DMG="dist/cLockIn-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Release builds are signed ad hoc: a personal certificate isn't trusted on other Macs anyway.
UNIVERSAL=1 VERSION="$VERSION" CODESIGN_IDENTITY="-" ./scripts/build-app.sh

ditto build/cLockIn.app "$STAGE/cLockIn.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/If macOS blocks the app.txt" <<'TEXT'
cLockIn isn't from the App Store, so the first time you open it macOS may say it can't be opened.

1. Drag cLockIn into the Applications folder and open it once.
2. Open System Settings > Privacy & Security.
3. Scroll down and click "Open Anyway" next to the message about cLockIn, then confirm.

You only need to do this once. cLockIn lives in the menu bar and the notch, not the Dock.
TEXT

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "cLockIn $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
shasum -a 256 "$DMG" | sed 's#dist/##' > "$DMG.sha256"
echo "Built $DMG"
