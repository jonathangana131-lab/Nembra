#!/usr/bin/env python3
"""Fail when an Xcode project references an object ID with no object definition.

`plutil -lint` verifies OpenStep plist syntax, but it does not detect dangling PBX
object references. This lightweight check catches that class of hand-edited
project-file mistake without pretending to replace an actual Xcode build.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

OBJECT_ID = re.compile(r"\b[A-F0-9]{24}\b")
OBJECT_DEFINITION = re.compile(
    r"^\s*([A-F0-9]{24})(?: /\*.*?\*/)?\s*=\s*\{",
    re.MULTILINE,
)


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "Nembra.xcodeproj/project.pbxproj")
    text = path.read_text(encoding="utf-8")
    referenced = set(OBJECT_ID.findall(text))
    defined = set(OBJECT_DEFINITION.findall(text))
    missing = sorted(referenced - defined)

    if missing:
        print(f"{path}: dangling PBX object references:", file=sys.stderr)
        for object_id in missing:
            print(f"  {object_id}", file=sys.stderr)
        return 1

    print(f"{path}: {len(defined)} PBX object references resolved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
