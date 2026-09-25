#!/bin/bash
# One-time: a self-signed "Convey Development" code-signing identity in the login keychain.
# Ad-hoc signatures change with every build, and macOS ties Screen Recording grants to the
# signature, so each `make run` silently revoked the grant. A fixed certificate keeps it.
set -euo pipefail
name="Convey Development"
if security find-certificate -c "$name" >/dev/null 2>&1; then echo "$name already exists"; exit 0; fi
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:convey
security import "$tmp/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P convey -T /usr/bin/codesign
echo "created $name — make run now signs with it (remove: security delete-identity -c \"$name\")"
