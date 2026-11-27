#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
configuration="${CONFIGURATION:-release}"
swift build --build-system native -c "$configuration" --product Airtype
binary_dir="$(swift build --build-system native -c "$configuration" --show-bin-path)"
app="$AIRTYPE_ROOT/build/Airtype.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Airtype" "$app/Contents/MacOS/Airtype"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Airtype.entitlements --sign "$SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - --entitlements Resources/Airtype.entitlements "$app"
fi
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
echo "$app"
