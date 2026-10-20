#!/bin/bash

# Build and run the self-tests in Tests/ against Sources/ (without HeadroomApp.swift, which
# has @main). They keep their state in a preferences domain of their own, deleted afterwards
# along with the empty plist macOS leaves for it.
set -euo pipefail
cd "$(dirname "$0")/.."

sources=()
for file in Sources/*.swift; do
    [[ $file == Sources/HeadroomApp.swift ]] || sources+=("$file")
done

mkdir -p build
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" -o build/HeadroomTests "${sources[@]}" Tests/*.swift
status=0
build/HeadroomTests || status=$?
defaults delete io.github.videlov.headroom.tests 2>/dev/null || true
rm -f ~/Library/Preferences/io.github.videlov.headroom.tests.plist
exit $status
