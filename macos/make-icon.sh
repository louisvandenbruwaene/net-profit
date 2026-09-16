#!/bin/sh
# Package the primary, user-supplied PNG as a native macOS icon.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
icon_source="$project_dir/assets/net-profit.png"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
icon_set="$work/net-profit.iconset"
mkdir -p "$icon_set"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
            512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  px=${spec%%:*}
  name=${spec##*:}
  sips -z "$px" "$px" "$icon_source" --out "$icon_set/$name.png" >/dev/null
done
iconutil -c icns "$icon_set" -o "$project_dir/assets/net-profit.icns"
printf '%s\n' "Wrote $project_dir/assets/net-profit.icns"
