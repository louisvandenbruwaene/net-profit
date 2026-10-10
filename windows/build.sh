#!/bin/sh
# Builds dist/net-profit-windows.zip: a fused Windows build anyone can unzip and
# run, no LÖVE install needed. LÖVE runs a .love archive appended to its own
# executable, so the game is just love.exe with game.love glued to the end,
# shipped beside the DLLs it links against.
set -eu
cd "$(dirname "$0")/.."

LOVE_VERSION=11.5
CACHE=dist/cache
WIN="love-$LOVE_VERSION-win64"
OUT=dist/windows/NetProfit

mkdir -p "$CACHE"
if [ ! -d "$CACHE/$WIN" ]; then
  curl -fsSL -o "$CACHE/$WIN.zip" \
    "https://github.com/love2d/love/releases/download/$LOVE_VERSION/$WIN.zip"
  unzip -q -o "$CACHE/$WIN.zip" -d "$CACHE"
fi

make -s dist >/dev/null
rm -rf dist/windows
mkdir -p "$OUT"
cat "$CACHE/$WIN/love.exe" dist/net-profit.love > "$OUT/NetProfit.exe"
cp "$CACHE/$WIN"/*.dll "$OUT/"
cp "$CACHE/$WIN/license.txt" "$OUT/love-license.txt"
cp README.md "$OUT/"

rm -f dist/net-profit-windows.zip
(cd dist/windows && zip -9 -q -r ../net-profit-windows.zip NetProfit)
echo "dist/net-profit-windows.zip"
