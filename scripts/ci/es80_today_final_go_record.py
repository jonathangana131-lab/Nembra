#!/usr/bin/env python3
"""Non-authorizing compatibility import for the V14 TODAY Final GO foundation.

Historical importers may continue to read foundation constants/helpers from this path, but this
module cannot build or publish a Final GO record. The only executable authority path is
``es80_today_final_go_hardened.py``. Foundation behavior tests target the explicit foundation
module rather than using this compatibility surface as an authority proxy.
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

# Keep the historical read/import surface available while authority-bearing entrypoints fail closed.
# The explicit foundation module owns the validator; the hardened executable is its only GO caller.
for _name in dir(_foundation):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_foundation, _name)


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    del args, kwargs
    raise FinalGoError(
        "legacy Final GO compatibility import is non-authorizing; "
        "use es80_today_final_go_hardened.py"
    )


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
