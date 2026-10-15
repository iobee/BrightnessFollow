#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
output_app=${1:-"$project_dir/.build/app/BrightnessFollow.app"}
signing_identity=${BRIGHTNESS_FOLLOW_SIGNING_IDENTITY:-"BrightnessFollow Local Code Signing"}
release_mode=${BRIGHTNESS_FOLLOW_RELEASE:-0}
if [[ "$release_mode" != 0 && "$release_mode" != 1 ]]; then
  echo "BRIGHTNESS_FOLLOW_RELEASE must be 0 or 1." >&2
  exit 3
fi
if [[ "$release_mode" == 1 && "$signing_identity" != 'Developer ID Application: '* ]]; then
  echo "Release builds require a Developer ID Application identity." >&2
  exit 3
fi
keychain_args=()
if [[ -n "${BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN:-}" ]]; then
  keychain_args=("$BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN")
fi
if ! security find-identity -v -p codesigning "${keychain_args[@]}" | grep -Fq "\"$signing_identity\""; then
  echo "Missing stable code signing identity: $signing_identity" >&2
  echo "For distribution, configure .env.release.local and run Scripts/release.sh." >&2
  echo "For local development, run Scripts/create-local-signing-identity.sh once." >&2
  echo "Refusing ad-hoc signing because it invalidates Accessibility permission after each rebuild." >&2
  exit 3
fi
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/brightness-follow.XXXXXX")
stage_app="$stage_root/BrightnessFollow.app"
trap 'rm -rf -- "$stage_root"' EXIT
module_cache="${TMPDIR:-/tmp}/brightness-follow-module-cache"

mkdir -p "$module_cache"
export CLANG_MODULE_CACHE_PATH="$module_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$module_cache"

cd "$project_dir"
swift build --disable-sandbox -c release --arch arm64

mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
cp ".build/arm64-apple-macosx/release/BrightnessFollow" "$stage_app/Contents/MacOS/BrightnessFollow"
cp "Resources/Info.plist" "$stage_app/Contents/Info.plist"
cp "LICENSE" "MONITORCONTROL_LICENSE.txt" "THIRD_PARTY_NOTICES.md" "$stage_app/Contents/Resources/"
"$project_dir/Scripts/build-icon.sh" \
  "$stage_app/Contents/Resources/AppIcon.icns" \
  "$stage_app/Contents/Resources/Assets.car"

signing_args=(--force --sign "$signing_identity")
if [[ -n "${BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN:-}" ]]; then
  signing_args+=(--keychain "$BRIGHTNESS_FOLLOW_SIGNING_KEYCHAIN")
fi
if [[ "$release_mode" == 1 || "$signing_identity" == 'Developer ID Application: '* ]]; then
  codesign "${signing_args[@]}" --options runtime --timestamp "$stage_app"
else
  codesign "${signing_args[@]}" --timestamp=none "$stage_app"
fi
codesign --verify --deep --strict "$stage_app"

if [[ -e "$output_app" ]]; then
  backup_app="${output_app}.previous"
  if [[ -e "$backup_app" ]]; then
    echo "Refusing to replace existing backup: $backup_app" >&2
    exit 2
  fi
  mv "$output_app" "$backup_app"
fi

mkdir -p "${output_app:h}"
mv "$stage_app" "$output_app"
echo "$output_app"
