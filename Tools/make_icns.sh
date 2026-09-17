#!/bin/bash
# Generates Resources/AppIcon.icns from Resources/icon-1024.png
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="Resources/icon-1024.png"
SET="build/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
  echo "Missing $SRC — run: swift Tools/make_icon.swift" >&2
  exit 1
fi

rm -rf "$SET"
mkdir -p "$SET"

while read -r px name; do
  [ -z "$px" ] && continue
  sips -z "$px" "$px" "$SRC" --out "$SET/icon_${name}.png" >/dev/null 2>&1
done <<'SIZES'
16 16x16
32 16x16@2x
32 32x32
64 32x32@2x
128 128x128
256 128x128@2x
256 256x256
512 256x256@2x
512 512x512
1024 512x512@2x
SIZES

iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
ls -la Resources/AppIcon.icns
