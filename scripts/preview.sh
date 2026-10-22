#!/bin/bash

# Render every page of the popup with sample data, dark and light, into build/preview/, with
# Liquid Glass (see screenshots/preview.swift). Pass scenario names (usage, banner, rejected,
# welcome, settings, cookie, services) to render only those. It keeps its state in
# a preferences domain of its own, deleted afterwards along with the empty plist macOS leaves.
set -euo pipefail
cd "$(dirname "$0")/.."

sources=()
for file in Sources/*.swift; do
    [[ $file == Sources/HeadroomApp.swift ]] || sources+=("$file")
done

mkdir -p build/preview
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -parse-as-library -o build/HeadroomPreview "${sources[@]}" screenshots/preview.swift
status=0
# A fixed locale, so the dates and times read the same on every Mac.
build/HeadroomPreview build/preview "$@" -AppleLocale en_DE || status=$?
defaults delete io.github.videlov.headroom.preview 2>/dev/null || true
rm -f ~/Library/Preferences/io.github.videlov.headroom.preview.plist
exit $status
