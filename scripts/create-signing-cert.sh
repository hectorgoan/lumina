#!/bin/bash
# Creates a self-signed "Lumina Development" code-signing certificate in the
# login keychain. scripts/build-app.sh signs with it, so every build has the
# same signing identity and macOS keeps Lumina's privacy permissions.
# It doesn't change any trust settings: codesign can sign with an untrusted
# certificate, and macOS only needs the signature to stay the same.
# Usage: scripts/create-signing-cert.sh
set -euo pipefail

CERT_NAME="Lumina Development"
KEYCHAIN="${LUMINA_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$CERT_NAME\""; then
    echo "A \"$CERT_NAME\" certificate is already in your login keychain."
    exit 0
fi

echo "This creates a self-signed code-signing certificate named \"$CERT_NAME\""
echo "(valid for 10 years) and adds it with its private key to your login keychain."
read -r -p "Continue? [y/N] " answer
case "$answer" in
    [yY]*) ;;
    *) echo "Cancelled."; exit 1 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# The system LibreSSL writes a PKCS#12 file that `security import` can read.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASSWORD="$(/usr/bin/openssl rand -hex 16)"
/usr/bin/openssl pkcs12 -export -name "$CERT_NAME" -passout "pass:$PASSWORD" \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12"

security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign

# Let codesign use the private key without a dialog on every build. This asks
# for your keychain (login) password; if you skip it, click Always Allow the
# first time a build asks instead.
echo "Enter your login password so codesign can use the key without asking:"
security set-key-partition-list -S apple-tool:,apple: -s -l "$CERT_NAME" "$KEYCHAIN" >/dev/null \
    || echo "Skipped. Click Always Allow when the first build asks for the key."

echo "Created \"$CERT_NAME\". The next build will be signed with it."
