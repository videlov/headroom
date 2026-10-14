#!/bin/bash

# Build build/Headroom.app for Apple silicon and Intel, signed with SIGNING_IDENTITY
# (default: the self-signed "videlov Code Signing" from make-signing-cert.sh; "-" = ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Headroom.app"
IDENTITY="${SIGNING_IDENTITY:-videlov Code Signing}"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/Headroom.icns "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"

for arch in arm64 x86_64; do
    swiftc -parse-as-library -O -swift-version 5 \
        -target "$arch-apple-macos12.0" \
        -o "build/Headroom-$arch" \
        Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/Headroom" build/Headroom-arm64 build/Headroom-x86_64
rm build/Headroom-arm64 build/Headroom-x86_64

# codesign rejects bundles with extended attributes ("resource fork, Finder information").
xattr -cr "$APP"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "✅ $APP, signed with \"$IDENTITY\""
