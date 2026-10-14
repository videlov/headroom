#!/bin/bash

# Make Resources/Headroom.icns from Resources/AppIcon.png (1024 × 1024).
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET="build/Headroom.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/Headroom.icns
rm -rf "$ICONSET"
echo "✅ Resources/Headroom.icns"
