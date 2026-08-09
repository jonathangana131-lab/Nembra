#!/usr/bin/env python3
"""Library-only compatibility surface for the V14 TODAY Final GO foundation.

The closed-world authority implementation is preserved byte-for-byte in
`es80_today_final_go_foundation_impl.py`. Importers may consume its constants, validation helpers,
and builder through this module, but direct execution is deliberately non-authorizing. The only
executable Final GO path is `es80_today_final_go_hardened.py`.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
from typing import Any

_IMPL_PATH = Path(__file__).with_name("es80_today_final_go_foundation_impl.py")
_spec = importlib.util.spec_from_file_location("nembra_today_final_go_foundation_impl", _IMPL_PATH)
if _spec is None or _spec.loader is None:
    raise RuntimeError("could not load Final GO foundation implementation")
_impl = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_impl)

for _name in dir(_impl):
    if not _name.startswith("__"):
        globals()[_name] = getattr(_impl, _name)


def build_final_go_record(*args: Any, **kwargs: Any) -> dict[str, Any]:
    """Delegate to the preserved implementation while honoring intentional injectable seams."""
    original_git = _impl._git
    original_trusted_xcode_subject = _impl._trusted_xcode_subject
    _impl._git = globals().get("_git", original_git)
    _impl._trusted_xcode_subject = globals().get(
        "_trusted_xcode_subject", original_trusted_xcode_subject
    )
    try:
        return _impl.build_final_go_record(*args, **kwargs)
    finally:
        _impl._git = original_git
        _impl._trusted_xcode_subject = original_trusted_xcode_subject


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: foundation module is library-only and non-authorizing; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
