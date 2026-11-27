#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/toolchain.sh"
bash scripts/test-swift.sh
uv sync --project research --frozen --no-editable
uv run --project research --no-editable pytest research/tests
uv run --project research --no-editable ruff check research
plutil -lint Resources/Info.plist Resources/Airtype.entitlements
python3 scripts/validate_docs.py
