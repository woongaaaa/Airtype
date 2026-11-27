#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
# Current standalone CLT installs Testing.framework outside SwiftPM's default path.
# Explicitly select Swift Testing; XCTest is neither used nor required.
if [ "${DEVELOPER_DIR:-}" = /Library/Developer/CommandLineTools ]; then
  frameworks="$DEVELOPER_DIR/Library/Developer/Frameworks"
  swift test --build-system native --disable-xctest -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks"
else
  swift test --build-system native --disable-xctest
fi
