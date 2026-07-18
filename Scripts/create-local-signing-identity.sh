#!/bin/zsh

set -euo pipefail

identity_name="BrightnessFollow Local Code Signing"
keychain_path=$(security default-keychain -d user | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

if security find-identity -v -p codesigning "$keychain_path" | grep -Fq "\"$identity_name\""; then
  echo "Code signing identity already exists: $identity_name"
  exit 0
fi

stage_root=$(mktemp -d "${TMPDIR:-/tmp}/brightness-follow-signing.XXXXXX")
private_key="$stage_root/private-key.pem"
certificate="$stage_root/certificate.pem"
identity_archive="$stage_root/identity.p12"
p12_password=$(openssl rand -hex 24)

cleanup() {
  rm -rf -- "$stage_root"
}
trap cleanup EXIT

openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$private_key" \
  -out "$certificate" \
  -subj "/CN=$identity_name/O=BrightnessFollow Local" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign" \
  -addext "extendedKeyUsage=codeSigning"

openssl pkcs12 -export -legacy \
  -inkey "$private_key" \
  -in "$certificate" \
  -name "$identity_name" \
  -out "$identity_archive" \
  -passout "pass:$p12_password"

security import "$identity_archive" \
  -k "$keychain_path" \
  -P "$p12_password" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$keychain_path" \
  "$certificate"

if ! security find-identity -v -p codesigning "$keychain_path" | grep -Fq "\"$identity_name\""; then
  echo "The identity was imported but is not available to codesign." >&2
  exit 1
fi

echo "Created code signing identity: $identity_name"
