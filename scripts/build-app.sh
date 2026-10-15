#!/bin/bash
# Builds Lumina with SwiftPM and wraps the binary into a signed .app bundle.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Lumina.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lumina" "$APP/Contents/MacOS/Lumina"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# A fresh build number per build, so macOS caches (like Notification Center's
# copy of the app icon) see each build as a new version.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"

# Refresh Launch Services so Finder and Notification Center pick up the icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Built $APP"
