#!/bin/bash

# Package build/Headroom.app as build/Headroom.dmg: the app plus a link to drag it onto
# /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/Headroom.app "$STAGE/Headroom.app"
ln -s /Applications "$STAGE/Applications"

rm -f build/Headroom.dmg
hdiutil create -quiet -volname Headroom -srcfolder "$STAGE" -ov -format UDZO build/Headroom.dmg
rm -rf "$STAGE"

echo "✅ build/Headroom.dmg"
shasum -a 256 build/Headroom.dmg
