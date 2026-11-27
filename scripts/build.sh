#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
configuration="${CONFIGURATION:-release}"
swift build --build-system native -c "$configuration" --product Airtype
binary_dir="$(swift build --build-system native -c "$configuration" --show-bin-path)"
app="$AIRTYPE_ARTIFACT_ROOT/Airtype.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Airtype" "$app/Contents/MacOS/Airtype"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
# Finder/iCloud may attach metadata to an inspected build bundle. Remove only
# signing-incompatible metadata from this generated artifact, never quarantine.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements Resources/Airtype.entitlements --sign "$SIGNING_IDENTITY" "$app"
else
  codesign --force --sign - --entitlements Resources/Airtype.entitlements "$app"
fi
plutil -lint "$app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$app"
mkdir -p "$AIRTYPE_ROOT/build"
if [ -d "$AIRTYPE_ROOT/build/Airtype.app" ] && [ ! -L "$AIRTYPE_ROOT/build/Airtype.app" ]; then
  mv "$AIRTYPE_ROOT/build/Airtype.app" "$AIRTYPE_ROOT/build/Airtype-icloud-backup-$(date +%s).app"
fi
ln -sfn "$app" "$AIRTYPE_ROOT/build/Airtype.app"
echo "$app"
