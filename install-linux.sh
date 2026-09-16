#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
data_dir=${XDG_DATA_HOME:-"$HOME/.local/share"}
game_dir="$data_dir/net-profit"
archive="$project_dir/net-profit.love"
if [ ! -f "$archive" ]; then archive="$project_dir/dist/net-profit.love"; fi
if [ ! -f "$archive" ]; then
  printf '%s\n' 'Build the game with make dist first.' >&2
  exit 1
fi
if ! command -v love >/dev/null 2>&1; then
  printf '%s\n' 'Install the LOVE 11.x runtime, then run this installer again.' >&2
  exit 1
fi

install -d "$game_dir" "$data_dir/applications" "$data_dir/pixmaps"
install -m 644 "$archive" "$game_dir/net-profit.love"
install -m 644 "$project_dir/assets/net-profit.png" "$data_dir/pixmaps/net-profit.png"
# Escape desktop-entry quoted argument syntax, including literal percent signs.
exec_path=$(printf '%s' "$game_dir/net-profit.love" | sed 's/\\/\\\\\\\\/g; s/"/\\\\"/g; s/`/\\\\`/g; s/\$/\\\\$/g; s/%/%%/g')
printf '%s\n' \
  '[Desktop Entry]' \
  'Version=1.0' \
  'Type=Application' \
  'Name=Net Profit' \
  'Comment=Build a network. Grow a utility company.' \
  "Exec=love \"$exec_path\"" \
  'TryExec=love' \
  'Icon=net-profit' \
  'Terminal=false' \
  'Categories=Game;StrategyGame;' \
  'Keywords=water;network;pipes;business;simulation;' \
  > "$data_dir/applications/net-profit.desktop"
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$data_dir/applications/net-profit.desktop"
fi
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data_dir/applications"
fi
printf '%s\n' 'Installed. Open Net Profit from your application menu.'
