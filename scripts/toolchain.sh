#!/bin/bash
# Sourced by build/check scripts. Never accepts the Xcode license on behalf of a user.
set -euo pipefail
AIRTYPE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! xcrun swift --version >/dev/null 2>&1; then
  if [ -x /Library/Developer/CommandLineTools/usr/bin/swift ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
  else
    echo 'Install Xcode/Command Line Tools and complete their setup first.' >&2
    exit 1
  fi
fi
cd "$AIRTYPE_ROOT"
