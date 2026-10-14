#!/bin/bash
set -euo pipefail

# This helper only operates on an ephemeral GitHub-hosted runner.
[[ "${GITHUB_ACTIONS:-}" == true && -n "${RUNNER_TEMP:-}" ]] || { echo 'Run this helper in GitHub Actions.' >&2; exit 1; }
keychain="$RUNNER_TEMP/release-signing.keychain-db"
certificate="$RUNNER_TEMP/release-signing.p12"
if [[ "${1:-}" == cleanup ]]; then
  security delete-keychain "$keychain" 2>/dev/null || true
  rm -f -- "$certificate"
  exit 0
fi
[[ "${1:-}" == setup ]] || { echo 'Usage: ci-signing.sh setup|cleanup' >&2; exit 1; }
for name in MACOS_SIGN_IDENTITY MACOS_TEAM_ID MACOS_CERTIFICATE_BASE64 MACOS_CERTIFICATE_PASSWORD APPLE_ID APPLE_APP_SPECIFIC_PASSWORD; do
  [[ -n "${!name:-}" ]] || { echo "Missing signing configuration: $name" >&2; exit 1; }
done
[[ "$MACOS_SIGN_IDENTITY" == "Developer ID Application: "*" ($MACOS_TEAM_ID)" ]] || { echo 'Developer ID/team mismatch.' >&2; exit 1; }
umask 077
trap 'rm -f -- "$certificate"' EXIT
keychain_password=$(openssl rand -hex 24)
echo "::add-mask::$keychain_password"
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$certificate"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
security list-keychains -d user -s "$keychain"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain" | grep -F "\"$MACOS_SIGN_IDENTITY\"" >/dev/null
xcrun notarytool store-credentials release-notary --keychain "$keychain" --apple-id "$APPLE_ID" --team-id "$MACOS_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
