#!/usr/bin/env bash
# One local identity per checkout. Never regenerate an existing identity silently.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING="$ROOT/.signing"
KEYCHAIN="$SIGNING/WubiCoach.keychain-db"
PASSWORD_FILE="$SIGNING/keychain-password"
CERTIFICATE="$SIGNING/certificate.der"
if [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" && -f "$CERTIFICATE" && -f "$SIGNING/identity-ready" ]]; then
  echo "Reusing WubiCoach local signing identity."
  exit 0
fi
if [[ -e "$SIGNING" ]]; then
  echo "Incomplete .signing directory; restore its original certificate/keychain instead of replacing the signing identity." >&2
  exit 1
fi

umask 077
mkdir -m 700 "$SIGNING"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/wubi-signing.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
openssl rand -base64 36 > "$PASSWORD_FILE"
PASSWORD="$(cat "$PASSWORD_FILE")"
cat > "$WORK/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = signing
prompt = no
[subject]
CN = WubiCoach Local Development
O = WubiCoach Local
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 -sha256 \
  -config "$WORK/certificate.cnf" -keyout "$WORK/private.key" -out "$WORK/certificate.pem" 2> "$WORK/openssl.log"
openssl x509 -in "$WORK/certificate.pem" -outform DER -out "$CERTIFICATE"
openssl pkcs12 -export -inkey "$WORK/private.key" -in "$WORK/certificate.pem" \
  -name "WubiCoach Local Development" -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -out "$WORK/identity.p12" -passout "file:$PASSWORD_FILE"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" > /dev/null
chmod 600 "$PASSWORD_FILE" "$KEYCHAIN" "$CERTIFICATE"
touch "$SIGNING/identity-ready"
echo "Created persistent WubiCoach signing identity in .signing (excluded from Git)."
