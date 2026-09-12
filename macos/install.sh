#!/bin/sh
# Builds a self-contained "Net Profit.app" in ~/Applications.
#
# The app used to be a two-line wrapper that ran LOVE against the source
# checkout in ~/Documents. That works, but it makes macOS ask for permission to
# read your Documents folder every time, because as far as TCC is concerned an
# unsigned app is reaching into a protected directory. It also breaks the moment
# the checkout moves, and it cannot carry its own icon.
#
# So instead we do what a shipped LOVE game does: copy LOVE itself, fuse the
# game into it as Resources/game.love, give it our icon and identity, and sign
# it ad-hoc. The result touches nothing outside its own bundle, asks for no
# permissions at all, and keeps working if love.app is moved or removed.
#
# Saves are unaffected: the identity in conf.lua still points at
# ~/Library/Application Support/LOVE/net-profit, so an existing company is
# picked up exactly as before.
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_dir="$HOME/Applications/Net Profit.app"
contents="$app_dir/Contents"
resources="$contents/Resources"

love_app=/Applications/love.app
[ -d "$love_app" ] || love_app="$HOME/Applications/love.app"
if [ ! -d "$love_app" ]; then
  printf '%s\n' 'LOVE is not installed. Download the macOS build from https://love2d.org/ and move love.app to /Applications, then run this installer again.' >&2
  exit 1
fi

# 1. Package the game.
mkdir -p "$project_dir/dist"
( cd "$project_dir" && rm -f dist/net-profit.love \
  && zip -FS -9 -r dist/net-profit.love main.lua conf.lua src assets -x '*.git*' >/dev/null )

# 2. Start from a clean copy of LOVE.
mkdir -p "$HOME/Applications"
rm -rf "$app_dir"
cp -R "$love_app" "$app_dir"

# 3. Fuse the game. LOVE runs Resources/game.love automatically when present.
cp "$project_dir/dist/net-profit.love" "$resources/game.love"

# 4. Our icon, and only our icon. Modern macOS prefers the compiled asset
#    catalog over CFBundleIconFile, so LOVE's has to go or its heart keeps
#    showing up in the Dock.
rm -f "$resources/Assets.car" "$resources/GameIcon.icns" "$resources/OS X AppIcon.icns"
cp "$project_dir/assets/net-profit.icns" "$resources/net-profit.icns"

# 5. Identity. Dropping the document declarations stops the game claiming to be
#    an editor for .love files, folders and every document type on the machine,
#    which is what made it look like an app that wants your files.
plist="$contents/Info.plist"
pb=/usr/libexec/PlistBuddy
set +e
$pb -c "Delete :CFBundleDocumentTypes" "$plist" >/dev/null 2>&1
$pb -c "Delete :UTExportedTypeDeclarations" "$plist" >/dev/null 2>&1
$pb -c "Delete :UTImportedTypeDeclarations" "$plist" >/dev/null 2>&1
$pb -c "Delete :NSServices" "$plist" >/dev/null 2>&1
$pb -c "Delete :CFBundleIconName" "$plist" >/dev/null 2>&1
$pb -c "Delete :CFBundleURLTypes" "$plist" >/dev/null 2>&1
set -e
# LOVE's plist does not define every key we want, so each one is set if it is
# there and added if it is not.
plset() {
  key=$1; type=$2; value=$3
  $pb -c "Set :$key $value" "$plist" >/dev/null 2>&1 \
    || $pb -c "Add :$key $type $value" "$plist" >/dev/null 2>&1 \
    || printf 'Warning: could not set %s\n' "$key" >&2
}
plset CFBundleName                string "Net Profit"
plset CFBundleDisplayName         string "Net Profit"
plset CFBundleIconFile            string "net-profit"
plset CFBundleIdentifier          string "eu.vandenbruwaene.netprofit"
plset CFBundleShortVersionString  string "1.2"
plset CFBundleVersion             string "1.2"
plset NSHighResolutionCapable     bool   true
plset LSApplicationCategoryType   string "public.app-category.simulation-games"

# 6. No quarantine flag, and an ad-hoc signature so the system has one stable
#    identity for this app instead of treating every launch as a new stranger.
xattr -cr "$app_dir" 2>/dev/null || true
if ! codesign --force --deep --sign - "$app_dir" >/dev/null 2>&1; then
  printf '%s\n' 'Warning: could not sign the app; it will still run.' >&2
fi

# 7. Nudge Finder and the icon cache so the new icon shows immediately.
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$app_dir" >/dev/null 2>&1 || true

printf '%s\n' "Installed $app_dir"
printf '%s\n' 'It is self-contained: no Documents access, no permission prompts.'
printf '%s\n' 'Re-run this after changing the source, or use "make run" to play the checkout directly.'
