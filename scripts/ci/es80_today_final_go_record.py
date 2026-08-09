#!/usr/bin/env python3
"""Compatibility import shim for the V14 ES80 TODAY Final GO foundation.

The historical filename remains importable for existing tests and tooling, but it is no longer an
executable Final GO authority. The only executable GO path is es80_today_final_go_hardened.py,
which binds owner-commanded default-branch Xcode authority and failure-atomic publication.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys

_FOUNDATION_PATH = Path(__file__).with_name("es80_today_final_go_foundation.py")
_spec = importlib.util.spec_from_file_location("nembra_final_go_foundation_compat", _FOUNDATION_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation")
_foundation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_foundation)

for _name in dir(_foundation):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_foundation, _name)

_foundation_build_final_go_record = _foundation.build_final_go_record


def build_final_go_record(*args, **kwargs):
    """Preserve the legacy import seam while honoring a caller-installed trusted-Xcode adapter."""
    previous = _foundation._trusted_xcode_subject
    _foundation._trusted_xcode_subject = globals()["_trusted_xcode_subject"]
    try:
        return _foundation_build_final_go_record(*args, **kwargs)
    finally:
        _foundation._trusted_xcode_subject = previous


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: legacy entrypoint disabled; use "
        "scripts/ci/es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
