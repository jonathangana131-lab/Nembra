#!/usr/bin/env python3
"""Non-authorizing compatibility surface for V14 TODAY Final GO constants and errors.

The authority-bearing closed-world validator lives in `_es80_today_final_go_foundation_impl.py` and
is consumed directly only by the canonical hardened composer plus adversarial test harnesses. This
public compatibility filename deliberately cannot mint or publish a Final GO record.

Only immutable/data-like compatibility names plus `FinalGoError` are copied from the private module.
No private implementation function object or loaded module object is retained here, so callers
cannot recover the private builder through this public namespace's delegated callable globals.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any

_IMPL_PATH = Path(__file__).with_name("_es80_today_final_go_foundation_impl.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation_impl", _IMPL_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation implementation")
_impl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_impl)

for _name in dir(_impl):
    if _name == "FinalGoError" or _name.isupper():
        globals()[_name] = getattr(_impl, _name)

del _impl
del _spec
del _name
del _IMPL_PATH

# Keep these exact source pins visible to canonical source-shape QA.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"


def _non_authorizing_error(surface: str) -> None:
    raise FinalGoError(
        f"public Final GO foundation {surface} is non-authorizing; "
        "use es80_today_final_go_hardened.py"
    )


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Fail closed: imported callers must use the canonical hardened composer instead."""
    del args, kwargs
    _non_authorizing_error("builder")


def publish_record_no_replace(*args: Any, **kwargs: Any) -> str:
    """Fail closed: publication authority also belongs only to the hardened composer."""
    del args, kwargs
    _non_authorizing_error("publisher")


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: Final GO foundation is non-authorizing when executed directly; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
