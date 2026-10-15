#!/bin/bash
# Builds Lumina with SwiftPM and wraps the binary into a signed .app bundle,
# with Sparkle.framework embedded.
# Usage: scripts/build-app.sh [debug|release]
# Set LUMINA_VERSION to override the version from Resources/Info.plist.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Lumina.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Lumina" "$APP/Contents/MacOS/Lumina"
# -R keeps the framework's internal symlinks intact.
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${LUMINA_VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $LUMINA_VERSION" "$APP/Contents/Info.plist"
fi
# A fresh build number per build, so macOS caches (like Notification Center's
# copy of the app icon) see each build as a new version.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable identity when there is one, so macOS keeps Lumina's
# privacy permissions (Accessibility, Automation) across rebuilds. Ad hoc
# signatures change with every build, so macOS may ask for them again.
# Set LUMINA_SIGN_IDENTITY to pick an identity, or create the default one
# with scripts/create-signing-cert.sh.
CERT_NAME="Lumina Development"
IDENTITY="${LUMINA_SIGN_IDENTITY:-}"
LABEL="$IDENTITY"
if [ -z "$IDENTITY" ]; then
    # No -v: a self-signed certificate isn't trusted, but codesign can still use it.
    IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
        | awk -v name="\"$CERT_NAME\"" 'index($0, name) { print $2; exit }')"
    LABEL="$CERT_NAME ($IDENTITY)"
fi

if [ -n "$IDENTITY" ]; then
    echo "Signing with identity: $LABEL"
else
    echo "Signing ad hoc (no \"$CERT_NAME\" certificate; see README)"
    IDENTITY="-"
fi

# Sign from the inside out: Sparkle's helpers, then the framework, then the
# app, as Sparkle's documentation describes for builds outside Xcode.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" -o runtime "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" -o runtime --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" -o runtime "$SPARKLE/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" -o runtime "$SPARKLE/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" -o runtime "$SPARKLE"
codesign --force --sign "$IDENTITY" "$APP"

# Refresh Launch Services so Finder and Notification Center pick up the icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Built $APP"
