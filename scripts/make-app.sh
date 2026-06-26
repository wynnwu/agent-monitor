#!/usr/bin/env bash
#
# make-app.sh — package AgentM into a double-clickable, menu-bar-only .app bundle.
#
#   ./scripts/make-app.sh            # release build (default)
#   ./scripts/make-app.sh debug      # debug build
#
# Produces ./AgentM.app — open it (or double-click) to run. No Dock icon;
# look for the radiowaves icon in the menu bar (top-right).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
echo "Building AgentM ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/AgentM"
[ -x "$BIN" ] || { echo "error: built binary not found at $BIN" >&2; exit 1; }

APP="AgentM.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentM"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AgentM</string>
  <key>CFBundleDisplayName</key><string>Agent M</string>
  <key>CFBundleIdentifier</key><string>xyz.joystudios.agent-m</string>
  <key>CFBundleExecutable</key><string>AgentM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Build AppIcon.icns from docs/images/icon.png.
if [ -f docs/images/icon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" docs/images/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" docs/images/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign for local personal use (no Developer ID required to run it yourself).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc codesign skipped"

echo "Built: $(pwd)/$APP"
echo "Run it with:  open \"$(pwd)/$APP\"   (icon appears in the menu bar, not the Dock)"
