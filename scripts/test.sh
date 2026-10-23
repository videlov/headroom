#!/bin/bash

# Build and run the self-tests in Tests/ against Sources/ (without HeadroomApp.swift, which
# has @main). They keep their state in a preferences domain of their own, deleted afterwards
# along with the empty plist macOS leaves for it, and run in en_DE and Berlin time, so dates
# read the same on every Mac. With --coverage, they also report the coverage of each file in
# Sources/.
set -euo pipefail
cd "$(dirname "$0")/.."

coverage=""
[[ ${1:-} == --coverage ]] && coverage="-profile-generate -profile-coverage-mapping"

sources=()
for file in Sources/*.swift; do
    [[ $file == Sources/HeadroomApp.swift ]] || sources+=("$file")
done

mkdir -p build
# $coverage unquoted: no flags or two.
swiftc -swift-version 5 -target "$(uname -m)-apple-macos13.0" $coverage -o build/HeadroomTests "${sources[@]}" Tests/*.swift
status=0
TZ=Europe/Berlin LLVM_PROFILE_FILE=build/HeadroomTests.profraw build/HeadroomTests -AppleLocale en_DE || status=$?
defaults delete io.github.videlov.headroom.tests 2>/dev/null || true
rm -f ~/Library/Preferences/io.github.videlov.headroom.tests.plist
if [[ -n $coverage ]]; then
    xcrun llvm-profdata merge -sparse build/HeadroomTests.profraw -o build/HeadroomTests.profdata
    xcrun llvm-cov report build/HeadroomTests -instr-profile build/HeadroomTests.profdata \
        -show-region-summary=false -show-branch-summary=false "${sources[@]}"
fi
exit $status
