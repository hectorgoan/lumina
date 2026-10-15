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
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "Signing ad hoc (no \"$CERT_NAME\" certificate; see README)"
    codesign --force --sign - "$APP"
fi

# Refresh Launch Services so Finder and Notification Center pick up the icon.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Built $APP"
