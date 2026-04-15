#!/bin/bash
#
# Creates a persistent self-signed code signing certificate for SuperPaste.
# Run once. All future builds will use this stable identity so macOS TCC
# (Accessibility, Screen Recording) grants survive rebuilds.
#
set -euo pipefail

CERT_NAME="SuperPaste Developer"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

# ── Already installed? ──────────────────────────────────────────────
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${CERT_NAME}\""; then
    echo "Certificate '${CERT_NAME}' already exists."
    security find-identity -v -p codesigning | grep "${CERT_NAME}"
    exit 0
fi

echo "Creating self-signed code signing certificate: ${CERT_NAME}"
echo ""

# ── Generate cert via OpenSSL (LibreSSL-compatible) ─────────────────
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/openssl.cnf" << 'CNFEOF'
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no

[dn]
CN = SuperPaste Developer

[ext]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
CNFEOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "${WORK}/key.pem" \
    -out    "${WORK}/cert.pem" \
    -days   3650 -nodes \
    -config "${WORK}/openssl.cnf" 2>/dev/null

# ── Bundle as PKCS#12 and import ────────────────────────────────────
openssl pkcs12 -export \
    -out    "${WORK}/cert.p12" \
    -inkey  "${WORK}/key.pem" \
    -in     "${WORK}/cert.pem" \
    -passout pass:supersecret 2>/dev/null

security import "${WORK}/cert.p12" \
    -k "${KEYCHAIN}" \
    -P supersecret \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Trust the certificate for code signing (avoids manual Keychain Access step)
security add-trusted-cert -p basic -p codeSign "${WORK}/cert.pem" 2>/dev/null || true

echo ""
echo "Certificate imported. Verifying..."

# ── Verify ──────────────────────────────────────────────────────────
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${CERT_NAME}\""; then
    echo ""
    security find-identity -v -p codesigning | grep "${CERT_NAME}"
    echo ""
    echo "Done. On first build, macOS may ask to allow codesign to use this key."
    echo "Click 'Always Allow' and you won't be asked again."
    echo ""
    echo "After the first build with the new cert, go to:"
    echo "  System Settings > Privacy & Security > Accessibility"
    echo "  Toggle SuperPaste OFF then ON to bind the permission to the stable identity."
    echo "  This is a one-time step. All future rebuilds keep the same identity."
else
    echo ""
    echo "Certificate was imported but is not showing as a valid code signing identity."
    echo "Open Keychain Access, find '${CERT_NAME}', double-click it,"
    echo "expand Trust, set Code Signing to 'Always Trust', then close."
    exit 1
fi
