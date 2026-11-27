"""Catch broken local documentation links and accidental release certification."""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
errors = []
for path in [root / "README.md", root / "CONTRIBUTING.md", *root.glob("docs/**/*.md")]:
    if not path.exists():
        errors.append(f"Missing {path.relative_to(root)}")
        continue
    for target in re.findall(r"\]\(([^)]+)\)", path.read_text()):
        if "://" in target or target.startswith("#"):
            continue
        local = target.split("#")[0]
        if local and not (path.parent / local).exists():
            errors.append(f"{path.relative_to(root)}: broken link {target}")
gate = json.loads((root / "docs/release-gate.json").read_text())
if gate["qualified"] and not all(gate["checks"].values()):
    errors.append("qualified=true with incomplete release checks")
if errors:
    raise SystemExit("\n".join(errors))
print("Documentation links and release gate are consistent.")
