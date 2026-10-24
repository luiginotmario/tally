#!/usr/bin/env bash
# Builds build/Tally.app: the menu bar app, which is also the `tally` command.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(cat VERSION)
app=build/Tally.app

swift build -c release
bin=$(swift build -c release --show-bin-path)

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin/Tally" "$app/Contents/MacOS/Tally"
sed "s/__VERSION__/$version/g" Resources/Info.plist > "$app/Contents/Info.plist"

# Sign with a Developer ID if there's one in the keychain, otherwise ad-hoc for this Mac only.
identity=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)
if [ -n "$identity" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Tally.entitlements --sign "$identity" "$app"
else
  codesign --force --entitlements Resources/Tally.entitlements --sign - "$app"
fi
echo "✓ $app (signed: ${identity:-ad-hoc})"
