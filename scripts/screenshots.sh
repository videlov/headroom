#!/bin/bash

# Redraw the README screenshots in screenshots/ from the app's own views with sample data.
# screenshots/main.swift is compiled with Sources/ (without HeadroomApp.swift, which has
# @main). It keeps its state in a preferences domain of its own, deleted afterwards along
# with the empty plist macOS leaves for it.
set -euo pipefail
cd "$(dirname "$0")/.."

sources=()
for file in Sources/*.swift; do
    [[ $file == Sources/HeadroomApp.swift ]] || sources+=("$file")
done

mkdir -p build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -o build/HeadroomScreenshots "${sources[@]}" screenshots/main.swift
status=0
# A fixed locale, so the dates and times read the same on every Mac.
build/HeadroomScreenshots screenshots -AppleLocale en_DE || status=$?
defaults delete io.github.videlov.headroom.screenshots 2>/dev/null || true
rm -f ~/Library/Preferences/io.github.videlov.headroom.screenshots.plist
exit $status
