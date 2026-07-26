#!/bin/bash
# Creates a stable, self-signed code-signing identity for LOCAL DEV BUILDS.
#
# Why this exists: ad-hoc signing (CODE_SIGN_IDENTITY "-") gives every build a
# new cdhash, and macOS TCC binds Microphone/Accessibility grants to it. So
# every rebuild silently revoked the app's permissions — and worse, the System
# Settings toggle kept showing "Bulong ✓ enabled" while the running app was
# actually denied, which looks exactly like an app bug.
#
# Signing with a fixed certificate instead makes the designated requirement
#     identifier "com.armageddonvivas.Bulong" and certificate leaf = H"<cert>"
# which is stable across rebuilds, so a grant given once keeps working.
#
# This is DEV ONLY. Shipping builds use the real Developer ID via
# script/release.sh; this certificate is not trusted by Gatekeeper and must
# never be used for anything a user downloads.
#
# Run once:  script/make_dev_signing_identity.sh
set -euo pipefail

NAME="Bulong Dev Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "'$NAME' already exists — nothing to do."
  security find-certificate -c "$NAME" -Z 2>/dev/null | grep 'SHA-1 hash' || true
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<'EOF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=Bulong Dev Signing
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
  -keyout "$WORK/dev.key" -out "$WORK/dev.crt" -config "$WORK/cert.cnf" 2>/dev/null

# macOS cannot read OpenSSL 3.x's default PKCS12 MAC, so pin the legacy algorithms.
openssl pkcs12 -export -inkey "$WORK/dev.key" -in "$WORK/dev.crt" \
  -out "$WORK/dev.p12" -passout pass:bulong -name "$NAME" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

# -T /usr/bin/codesign pre-authorizes codesign to use the key without a prompt.
security import "$WORK/dev.p12" -k "$KEYCHAIN" -P bulong -T /usr/bin/codesign

echo
echo "Created '$NAME'."
echo "Note: it shows as an INVALID identity in \`security find-identity -v\` because"
echo "it is self-signed and untrusted. That is expected — codesign still uses it,"
echo "and a stable signature is the only thing we need here."
echo
echo "Next: script/dev_build.sh will sign with it automatically. Grant Microphone"
echo "and Accessibility once after the next build; they will persist from then on."
