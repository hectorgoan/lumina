#!/bin/bash
# One-time setup for the release workflow (.github/workflows/release.yml).
#
# 1. Creates (or reuses) Sparkle's update signing key in your login keychain,
#    writes its public half to Resources/Info.plist, and stores the private
#    half as the SPARKLE_PRIVATE_KEY repository secret.
# 2. Exports the "Lumina Development" signing certificate and stores it as the
#    LUMINA_CERT_P12 and LUMINA_CERT_PASSWORD secrets, so release builds keep
#    the same signature and macOS keeps Lumina's permissions across updates.
#
# Secrets go straight from your keychain to GitHub and are never printed.
# Requires the GitHub CLI (gh), signed in with access to the repository.
# Usage: scripts/setup-release-secrets.sh
set -euo pipefail

cd "$(dirname "$0")/.."

CERT_NAME="Lumina Development"
SPARKLE_VERSION="$(sed -n 's/.*Sparkle", exact: "\(.*\)").*/\1/p' Package.swift)"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

echo "This will:"
echo "  • create or reuse Sparkle's update signing key in your login keychain"
echo "  • set SUPublicEDKey in Resources/Info.plist"
echo "  • set the SPARKLE_PRIVATE_KEY, LUMINA_CERT_P12 and LUMINA_CERT_PASSWORD secrets on $REPO"
read -r -p "Continue? [y/N] " answer
case "$answer" in
    [yY]*) ;;
    *) echo "Cancelled."; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
umask 077

echo "Downloading Sparkle $SPARKLE_VERSION tools…"
curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "$TMP"

# Update signing key. macOS may ask to let generate_keys use the keychain.
"$TMP/bin/generate_keys" > /dev/null
PUBLIC_KEY="$("$TMP/bin/generate_keys" -p)"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" Resources/Info.plist
echo "Set SUPublicEDKey in Resources/Info.plist."

"$TMP/bin/generate_keys" -x "$TMP/sparkle-key" > /dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$TMP/sparkle-key"

# Signing certificate. macOS asks to allow exporting the key.
if security find-identity -p codesigning | grep -q "\"$CERT_NAME\""; then
    CERT_PASSWORD="$(openssl rand -hex 24)"
    swift scripts/export-signing-identity.swift "$CERT_NAME" "$TMP/cert.p12" "$CERT_PASSWORD"
    base64 -i "$TMP/cert.p12" | gh secret set LUMINA_CERT_P12 --repo "$REPO"
    printf '%s' "$CERT_PASSWORD" | gh secret set LUMINA_CERT_PASSWORD --repo "$REPO"
else
    echo "No \"$CERT_NAME\" certificate found; run scripts/create-signing-cert.sh first."
    echo "Without it, release builds are signed ad hoc."
fi

echo
echo "Done. Commit Resources/Info.plist so release builds include the public key."
