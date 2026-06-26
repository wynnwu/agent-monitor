#!/usr/bin/env bash
#
# make-dmg.sh — package AgentM.app into a distributable .dmg.
#
#   ./scripts/make-dmg.sh
#
# Builds the release .app (via make-app.sh) and produces ./AgentM-<version>.dmg
# with the app and an Applications shortcut for drag-to-install.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/make-app.sh release

APP="AgentM.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo 0.1.0)"
DMG="AgentM-${VERSION}.dmg"

STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "Agent M" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "Built: $(pwd)/$DMG"
