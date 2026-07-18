#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
output_app=${1:-"$project_dir/BrightnessFollow.app"}
signing_identity=${BRIGHTNESS_FOLLOW_SIGNING_IDENTITY:-"BrightnessFollow Local Code Signing"}
stage_root=$(mktemp -d "${TMPDIR:-/tmp}/brightness-follow.XXXXXX")
stage_app="$stage_root/BrightnessFollow.app"
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

if ! security find-identity -v -p codesigning | grep -Fq "\"$signing_identity\""; then
  echo "Missing stable code signing identity: $signing_identity" >&2
  echo "Run Scripts/create-local-signing-identity.sh once, then rebuild." >&2
  echo "Refusing ad-hoc signing because it invalidates Accessibility permission after each rebuild." >&2
  exit 3
fi

codesign --force --sign "$signing_identity" --timestamp=none "$stage_app"

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
