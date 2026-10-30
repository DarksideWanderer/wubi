#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?Usage: bash macos/sign.sh path/to/WubiCoach.app}"
IDENTIFIER="org.wubicoach.desktop"
if [[ -n "${WUBI_SIGN_IDENTITY:-}" ]]; then
  OPTIONS=()
  if [[ -n "${WUBI_SIGN_KEYCHAIN:-}" ]]; then OPTIONS+=(--keychain "$WUBI_SIGN_KEYCHAIN"); fi
  codesign --force --sign "$WUBI_SIGN_IDENTITY" --identifier "$IDENTIFIER" "${OPTIONS[@]}" "$APP"
elif [[ "${WUBI_ADHOC_SIGN:-0}" == 1 || "${CI:-false}" == true ]]; then
  echo "Using ad-hoc signing (CI/explicit opt-in); privacy authorization will not persist across changed builds."
  codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
else
  bash "$ROOT/macos/setup-signing.sh"
  SIGNING="$ROOT/.signing"
  KEYCHAIN="$SIGNING/WubiCoach.keychain-db"
  # codesign requires the identity keychain on the search list even with --keychain.
  KEYCHAINS=()
  while IFS= read -r line; do
    entry="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/')"
    [[ -n "$entry" ]] && KEYCHAINS+=("$entry")
  done < <(security list-keychains -d user)
  FOUND=0
  for entry in "${KEYCHAINS[@]}"; do [[ "$entry" == "$KEYCHAIN" ]] && FOUND=1; done
  if [[ "$FOUND" == 0 ]]; then security list-keychains -d user -s "${KEYCHAINS[@]}" "$KEYCHAIN"; fi
  security unlock-keychain -p "$(cat "$SIGNING/keychain-password")" "$KEYCHAIN"
  FINGERPRINT="$(openssl x509 -inform DER -in "$SIGNING/certificate.der" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
  REQUIREMENT="designated => identifier \"$IDENTIFIER\" and anchor H\"$FINGERPRINT\""
  codesign --force --sign "$FINGERPRINT" --keychain "$KEYCHAIN" --timestamp=none \
    --identifier "$IDENTIFIER" --requirements "=$REQUIREMENT" "$APP"
fi
codesign --verify --strict "$APP"
codesign --display --requirements - "$APP"
