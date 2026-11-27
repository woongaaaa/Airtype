#!/bin/bash
# Run manually only after completing docs/RELEASE.md and obtaining a Developer ID.
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
: "${SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set a notarytool keychain profile, never a plaintext secret}"
if [[ "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  echo 'A Developer ID Application signing identity is required.' >&2; exit 1
fi
if ! python3 -c 'import json; r=json.load(open("docs/release-gate.json")); assert r["qualified"] and all(r["checks"].values()), "Release gate is incomplete"'; then
  echo 'Complete and review the release evidence before notarizing.' >&2; exit 1
fi
bash scripts/build.sh
ditto -c -k --keepParent "$AIRTYPE_ARTIFACT_ROOT/Airtype.app" build/Airtype-notary.zip
xcrun notarytool submit build/Airtype-notary.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$AIRTYPE_ARTIFACT_ROOT/Airtype.app"
xcrun stapler validate "$AIRTYPE_ARTIFACT_ROOT/Airtype.app"
# package.sh normally rebuilds. Package this stapled app directly instead.
staging="$(mktemp -d "${TMPDIR:-/tmp}/airtype-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
mkdir -p dist
ditto "$AIRTYPE_ARTIFACT_ROOT/Airtype.app" "$staging/Airtype.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Airtype -srcfolder "$staging" -ov -format UDZO dist/Airtype-0.1.0-arm64.dmg
codesign --sign "$SIGNING_IDENTITY" --timestamp dist/Airtype-0.1.0-arm64.dmg
xcrun notarytool submit dist/Airtype-0.1.0-arm64.dmg --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple dist/Airtype-0.1.0-arm64.dmg
xcrun stapler validate dist/Airtype-0.1.0-arm64.dmg
shasum -a 256 dist/Airtype-0.1.0-arm64.dmg > dist/Airtype-0.1.0-arm64.dmg.sha256
