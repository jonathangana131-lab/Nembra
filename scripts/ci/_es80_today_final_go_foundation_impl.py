#!/usr/bin/env python3
"""Non-authorizing tombstone for the retired private Final GO implementation filename.

The reviewed closed-world validator bytes were preserved unchanged at
`_es80_today_final_go_foundation_library.py`. Canonical production composition and adversarial tests
consume that library filename directly. This historical `_impl.py` path intentionally exports no
record builder and cannot be executed to mint a Final GO record.
"""
from __future__ import annotations

import sys


def main(argv: list[str] | None = None) -> int:
    del argv
    print(
        "TODAY Final GO: NO-GO: retired private foundation implementation path is non-authorizing; "
        "use es80_today_final_go_hardened.py",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
