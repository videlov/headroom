#!/bin/bash

# Install build/Headroom.app into /Applications and start it, replacing a running copy.
set -euo pipefail
cd "$(dirname "$0")/.."

pkill -x Headroom 2>/dev/null || true
rm -rf /Applications/Headroom.app
ditto build/Headroom.app /Applications/Headroom.app
open /Applications/Headroom.app
echo "✅ /Applications/Headroom.app"
