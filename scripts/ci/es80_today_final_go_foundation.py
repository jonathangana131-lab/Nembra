#!/usr/bin/env python3
"""Non-authorizing public facade for the V14 TODAY Final GO foundation.

The authority-bearing validator is private implementation detail consumed only by the canonical
`es80_today_final_go_hardened.py` composition. This historical/public foundation filename remains
importable for constants and non-authorizing helpers, but it cannot build, publish, or execute a
Final GO record.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any

_IMPL_PATH = Path(__file__).with_name("_es80_today_final_go_foundation_impl.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation_impl", _IMPL_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load private Final GO foundation implementation")
_impl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_impl)

_BLOCKED_AUTHORITY_NAMES = {
    "_trusted_xcode_subject",
    "build_final_go_record",
    "publish_record_no_replace",
    "main",
}
for _name in dir(_impl):
    if not _name.startswith("__") and _name not in _BLOCKED_AUTHORITY_NAMES:
        globals()[_name] = getattr(_impl, _name)

FinalGoError = _impl.FinalGoError


def _authority_disabled() -> FinalGoError:
    return FinalGoError(
        "public Final GO foundation is non-authorizing; use es80_today_final_go_hardened.py"
    )


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    del args, kwargs
    raise _authority_disabled()


def publish_record_no_replace(*args: Any, **kwargs: Any) -> str:
    del args, kwargs
    raise _authority_disabled()


def main(argv: list[str] | None = None) -> int:
    del argv
    print(f"TODAY Final GO: NO-GO: {_authority_disabled()}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
