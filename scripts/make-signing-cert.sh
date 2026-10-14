#!/bin/bash

# Create the self-signed code-signing certificate that build.sh uses, in the login
# keychain. Run once per Mac. With a stable certificate, macOS treats each new build as
# the same app, so it keeps reading the cookie from the Keychain without asking. It is
# not an Apple certificate: releases are still not notarized.
set -euo pipefail

NAME="${1:-videlov Code Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate \"$NAME\" is already in the login keychain."
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = codesign
prompt = no
[ dn ]
CN = $NAME
[ codesign ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
P12_PASS="$(/usr/bin/openssl rand -hex 16)"
export P12_PASS
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout env:P12_PASS
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null

echo "✅ Created \"$NAME\" (valid for 10 years) in the login keychain."
