#!/bin/sh
# Regenerates assets/net-profit.icns from assets/net-profit.svg.
#
# There is no SVG rasteriser on this machine, but Brave is Chromium and will
# screenshot a page headlessly, and sips/iconutil ship with macOS. The .icns is
# committed, so the installer never needs any of this.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
brave="/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

{
  printf '%s' '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}svg{display:block;width:1024px;height:1024px}</style>'
  sed 's/width="256" height="256"/width="1024" height="1024"/' "$project_dir/assets/net-profit.svg"
} > "$work/icon.html"

"$brave" --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --default-background-color=00000000 --force-device-scale-factor=1 \
  --screenshot="$work/icon-1024.png" --window-size=1024,1024 \
  "file://$work/icon.html" >/dev/null 2>&1

set="$work/net-profit.iconset"
mkdir -p "$set"
for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
            512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x; do
  px=${spec%%:*}
  name=${spec##*:}
  sips -z "$px" "$px" "$work/icon-1024.png" --out "$set/$name.png" >/dev/null 2>&1
done
iconutil -c icns "$set" -o "$project_dir/assets/net-profit.icns"
printf '%s\n' "Wrote $project_dir/assets/net-profit.icns"
