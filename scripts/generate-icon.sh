#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f icon-source.png ]; then
    echo "No icon-source.png found, skipping icon generation"
    exit 0
fi

if [ -f AppIcon.icns ] && [ ! icon-source.png -nt AppIcon.icns ]; then
    echo "AppIcon.icns is up to date"
    exit 0
fi

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"

sips -z 16 16 icon-source.png --out "$ICONSET/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32 icon-source.png --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
sips -z 32 32 icon-source.png --out "$ICONSET/icon_32x32.png" > /dev/null 2>&1
sips -z 64 64 icon-source.png --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128 icon-source.png --out "$ICONSET/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256 icon-source.png --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256 icon-source.png --out "$ICONSET/icon_256x256.png" > /dev/null 2>&1
sips -z 512 512 icon-source.png --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512 icon-source.png --out "$ICONSET/icon_512x512.png" > /dev/null 2>&1
cp icon-source.png "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o AppIcon.icns
rm -rf "$ICONSET"
echo "Generated AppIcon.icns"
