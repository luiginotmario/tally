#!/usr/bin/env bash
# Builds Tally, puts it in /Applications, links the `tally` command, and starts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh
osascript -e 'quit app id "com.luigirivolta.tally"' 2>/dev/null || true
rm -rf /Applications/Tally.app
cp -R build/Tally.app /Applications/
mkdir -p ~/.local/bin
ln -sf /Applications/Tally.app/Contents/MacOS/Tally ~/.local/bin/tally
open /Applications/Tally.app
echo "✓ installed. Now: menu bar → Connect Agents… (or run: tally connect)"
