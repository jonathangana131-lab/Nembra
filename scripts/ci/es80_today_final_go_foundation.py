#!/usr/bin/env python3
"""Non-authorizing public facade for the V14 TODAY Final GO foundation.

Historical importers may continue to consume constants and validation helpers from this path, but
neither direct execution nor the public `build_final_go_record` callable can mint Final GO.
Authoritative composition lives only in `es80_today_final_go_hardened.py`, which loads the private
closed-world implementation directly and replaces candidate-controlled Xcode authority with the
owner-commanded default-branch subject.

The private implementation remains directly testable by repository adversarial harnesses. This
public facade intentionally does not provide an alternate composition path around the hardened
entrypoint.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any, NoReturn

_IMPL_PATH = Path(__file__).with_name("_es80_today_final_go_foundation_impl.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation_impl", _IMPL_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation implementation")
_impl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_impl)

# Preserve the existing constants and helper imports for compatibility. The authority-bearing
# builder is overwritten below before this module is exposed to callers.
for _name in dir(_impl):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_impl, _name)

# Keep these exact source pins visible to canonical source-shape QA while the private implementation
# remains byte-identical to the previously accepted closed-world validator.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"


def _non_authorizing_builder_error() -> NoReturn:
    raise FinalGoError(
        "public Final GO foundation builder is non-authorizing; "
        "use es80_today_final_go_hardened.py"
    )


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Fail closed: ordinary foundation imports are never a Final-GO authority surface."""
    del args, kwargs
    _non_authorizing_builder_error()


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: Final GO foundation is library-only and non-authorizing; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


# Do not retain the obvious module-object escape used by the former delegating public builder.
# Repository adversarial tests and the canonical hardened composer load the private implementation
# by its dedicated filename instead.
del _impl


if __name__ == "__main__":
    raise SystemExit(main())
