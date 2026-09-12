#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$HOME/Applications/Net Profit.app"
contents_dir="$app_dir/Contents"
resources_dir="$contents_dir/Resources"

if [ ! -d "/Applications/love.app" ] && [ ! -d "$HOME/Applications/love.app" ]; then
  printf '%s\n' 'LÖVE is not installed. Download the macOS build from https://love2d.org/ and move love.app to /Applications, then run this installer again.' >&2
  exit 1
fi

love_app=/Applications/love.app
[ -d "$love_app" ] || love_app="$HOME/Applications/love.app"

mkdir -p "$resources_dir"
cp "$project_dir/macos/Net Profit" "$contents_dir/Net Profit"
sed -i '' "s|__LOVE_APP__|$love_app|g; s|__PROJECT_DIR__|$project_dir|g" "$contents_dir/Net Profit"
cp "$project_dir/macos/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/assets/net-profit.svg" "$resources_dir/net-profit.svg"
chmod +x "$contents_dir/Net Profit"

printf '%s\n' "Installed $app_dir"
printf '%s\n' 'Open Net Profit from Launchpad, Finder, or Spotlight.'
