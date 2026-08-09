#!/usr/bin/env python3
"""Library-only compatibility surface for the V14 TODAY Final GO foundation.

The closed-world foundation implementation is preserved byte-for-byte in
`_es80_today_final_go_foundation_impl.py`. This public module exposes validation helpers and a
builder seam for the hardened composer, but it intentionally refuses two authority-bearing legacy
paths:
- direct execution cannot mint Final GO; and
- a caller-authored operator JSON file is not sufficient operator/device authority.

`es80_today_final_go_hardened.py` is the only executable Final GO composer. It must inject both the
trusted default-branch Xcode subject and the private live field rendezvous before delegating here.
"""
from __future__ import annotations

from datetime import datetime
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

# Keep these exact source pins visible to canonical source-shape QA while implementation remains
# byte-identical to the previously accepted closed-world validator.
PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
RESEARCH_COMPILE_MODE = "private-today-v1"
RESEARCH_COMPILE_AUTHORITY = "canonical-producer-explicit-mode"
RESEARCH_COMPILE_CONDITION = "NEMBRA_ES80_TODAY_RESEARCH"


def validate_operator_observation(
    path: Path,
    candidate: dict[str, Any],
    now_utc: datetime,
) -> dict[str, Any]:
    """Parse human observations without promoting them to Final-GO authority."""
    return _impl._operator_attestation(path, candidate, now_utc)


def _operator_attestation(
    path: Path,
    candidate: dict[str, Any],
    now_utc: datetime,
) -> dict[str, Any]:
    del path, candidate, now_utc
    raise FinalGoError(
        "caller-authored operator attestation is non-authorizing; hardened Final GO requires "
        "the private live field rendezvous"
    )


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Delegate while honoring only the hardened composer's injectable trust seams."""
    original_git = _impl._git
    original_trusted_xcode_subject = _impl._trusted_xcode_subject
    original_operator_attestation = _impl._operator_attestation
    _impl._git = globals().get("_git", original_git)
    _impl._trusted_xcode_subject = globals().get(
        "_trusted_xcode_subject", original_trusted_xcode_subject
    )
    _impl._operator_attestation = globals().get(
        "_operator_attestation", original_operator_attestation
    )
    try:
        return _impl.build_final_go_record(*args, **kwargs)
    finally:
        _impl._git = original_git
        _impl._trusted_xcode_subject = original_trusted_xcode_subject
        _impl._operator_attestation = original_operator_attestation


def publish_record_no_replace(*args: Any, **kwargs: Any) -> str:
    return _impl.publish_record_no_replace(*args, **kwargs)


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: Final GO foundation is library-only and non-authorizing when "
        "executed directly; use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
