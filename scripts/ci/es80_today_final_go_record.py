#!/usr/bin/env python3
"""Non-authorizing compatibility facade for the historical TODAY Final GO module.

The historical import and executable path must never mint Final GO authority. Safe constants and
non-authorizing helpers are forwarded from the public foundation facade. The only supported
executable authority path is `es80_today_final_go_hardened.py`.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any

_FOUNDATION_PATH = Path(__file__).with_name("es80_today_final_go_foundation.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_public_foundation", _FOUNDATION_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load public Final GO foundation facade")
_foundation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_foundation)

for _name in dir(_foundation):
    if not _name.startswith("__") and _name not in {"build_final_go_record", "publish_record_no_replace", "main"}:
        globals()[_name] = getattr(_foundation, _name)

FinalGoError = _foundation.FinalGoError


def _authority_disabled() -> FinalGoError:
    return FinalGoError(
        "historical Final GO import is non-authorizing; use es80_today_final_go_hardened.py"
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
