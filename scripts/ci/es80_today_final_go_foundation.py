#!/usr/bin/env python3
"""Non-authorizing compatibility surface for V14 TODAY Final GO foundation helpers.

The closed-world validator implementation lives in `_es80_today_final_go_foundation_impl.py` and is
consumed directly only by the canonical hardened composer plus adversarial test harnesses. This
public compatibility filename deliberately cannot mint a Final GO record either by direct execution
or by importing `build_final_go_record(...)`.

Helper constants/parsers remain re-exported temporarily so existing source-shape QA and closed-world
test fixtures can converge without reopening a second production authority path. The loaded private
implementation module itself is deliberately not retained as a public-module capability.
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
    if not _name.startswith("__"):
        globals()[_name] = getattr(_impl, _name)

# Preserve the non-authorizing publication helper without retaining a module object through which
# callers could recover the private authority-bearing builder.
_publish_impl = _impl.publish_record_no_replace
del _impl

# Keep these exact source pins visible to canonical source-shape QA while the private implementation
# remains the tested closed-world parser/validator.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Fail closed: imported callers must use the canonical hardened composer instead."""
    del args, kwargs
    raise FinalGoError(
        "public Final GO foundation builder is non-authorizing; use es80_today_final_go_hardened.py"
    )


def publish_record_no_replace(*args: Any, **kwargs: Any) -> str:
    """Retain publication helper compatibility without granting record-construction authority."""
    return _publish_impl(*args, **kwargs)


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
