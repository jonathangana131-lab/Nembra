#!/usr/bin/env python3
"""Non-authorizing compatibility import for the V14 TODAY Final GO foundation.

Historical importers may continue to consume constants and validation helpers from this path, but
neither direct execution nor the historical `build_final_go_record` callable can mint Final GO.
Authoritative composition lives only in `es80_today_final_go_hardened.py`, which loads the foundation
directly, replaces candidate-controlled Xcode authority with the owner-commanded default-branch
subject, and uses failure-atomic publication.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any, NoReturn

_FOUNDATION_PATH = Path(__file__).with_name("es80_today_final_go_foundation.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation", _FOUNDATION_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation")
_foundation = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_foundation)

# Preserve historical constants/helpers without preserving an authority-bearing builder. Dunder
# metadata stays owned by this compatibility module. The hardened executable loads the foundation
# directly and therefore does not depend on this compatibility surface for GO authority.
for _name in dir(_foundation):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_foundation, _name)


def _non_authorizing_builder_error() -> NoReturn:
    raise FinalGoError(
        "legacy Final GO compatibility builder is non-authorizing; "
        "use es80_today_final_go_hardened.py"
    )


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Fail closed: the historical import path is never a Final-GO authority surface."""
    del args, kwargs
    _non_authorizing_builder_error()


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: legacy foundation entrypoint is non-authorizing; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


# Do not retain an obvious module-object escape back to the authority-bearing foundation through
# this compatibility namespace. Private validation helpers were copied above for compatibility.
del _foundation


if __name__ == "__main__":
    raise SystemExit(main())
