#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
bash scripts/build.sh
mkdir -p dist
staging="$(mktemp -d "${TMPDIR:-/tmp}/airtype-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$AIRTYPE_ARTIFACT_ROOT/Airtype.app" "$staging/Airtype.app"
codesign --verify --strict "$staging/Airtype.app"
ln -s /Applications "$staging/Applications"
printf '%s\n' 'Airtype development preview — not release-qualified.' 'Drag Airtype to Applications. See README and docs/RELEASE.md.' > "$staging/READ-ME.txt"
name="Airtype-0.1.0-dev-arm64.dmg"
hdiutil create -volname 'Airtype Development Preview' -srcfolder "$staging" -ov -format UDZO "dist/$name"
shasum -a 256 "dist/$name" > "dist/$name.sha256"
echo "$AIRTYPE_ROOT/dist/$name"
