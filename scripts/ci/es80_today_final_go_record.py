#!/usr/bin/env python3
"""Compatibility import for the V14 TODAY Final GO foundation.

Importers may continue to consume the validated foundation API from this historical path, but direct
execution is deliberately non-authorizing. The only executable Final GO path is
`es80_today_final_go_hardened.py`, which replaces candidate-controlled Xcode authority with the
owner-commanded default-branch subject and uses failure-atomic publication.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any

_FOUNDATION_PATH = Path(__file__).with_name("es80_today_final_go_foundation.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation", _FOUNDATION_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation")
_foundation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_foundation)

# Preserve the historical import surface for tests and internal composition without copying or
# reimplementing the validated foundation. Dunder metadata stays owned by this compatibility module.
for _name in dir(_foundation):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_foundation, _name)


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Delegate to the foundation while honoring the two intentional injectable test/trust seams."""
    original_git = _foundation._git
    original_trusted_xcode_subject = _foundation._trusted_xcode_subject
    _foundation._git = globals().get("_git", original_git)
    _foundation._trusted_xcode_subject = globals().get(
        "_trusted_xcode_subject", original_trusted_xcode_subject
    )
    try:
        return _foundation.build_final_go_record(*args, **kwargs)
    finally:
        _foundation._git = original_git
        _foundation._trusted_xcode_subject = original_trusted_xcode_subject


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: legacy foundation entrypoint is non-authorizing; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
