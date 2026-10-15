#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
icon_document="$project_dir/Resources/AppIcon.icon"
icon_output=${1:-"$project_dir/Resources/AppIcon.icns"}
catalog_output=${2:-}
icon_stage=$(mktemp -d "${TMPDIR:-/tmp}/brightness-follow-icon.XXXXXX")
trap 'rm -rf "$icon_stage"' EXIT

if [[ ! -f "$icon_document/icon.json" ]]; then
  echo "Missing Icon Composer document: $icon_document" >&2
  exit 1
fi

# Xcode 26+ compiles both native appearance-aware layers and an ICNS fallback.
# Do not silently replace this with a PNG-only build: it loses the dark icon.
xcrun actool "$icon_document" \
  --compile "$icon_stage" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$icon_stage/IconInfo.plist" \
  --output-format human-readable-text --warnings --errors --notices

if [[ ! -s "$icon_stage/Assets.car" || ! -s "$icon_stage/AppIcon.icns" ]]; then
  echo "Native icon compilation failed. Use Xcode 26 or newer." >&2
  exit 1
fi

assetutil --info "$icon_stage/Assets.car" > "$icon_stage/catalog-info.json"
if ! grep -Fq '"Appearance" : "NSAppearanceNameDarkAqua"' "$icon_stage/catalog-info.json"; then
  echo "Compiled icon is missing its dark appearance." >&2
  exit 1
fi

mkdir -p "${icon_output:h}"
cp "$icon_stage/AppIcon.icns" "$icon_output"
if [[ -n "$catalog_output" ]]; then
  mkdir -p "${catalog_output:h}"
  cp "$icon_stage/Assets.car" "$catalog_output"
fi
printf '%s\n' "$icon_output"
