#!/usr/bin/env python3
"""One-shot exact source transform for the field xcrun selector fence."""
from pathlib import Path

INSTALLER = Path("scripts/field/install_one_time_capture.command")
OLD = """unset BASH_ENV ENV CDPATH || true
unset DEVELOPER_DIR || true
hash -r
"""
NEW = """unset BASH_ENV ENV CDPATH || true
unset DEVELOPER_DIR SDKROOT TOOLCHAINS || true
hash -r
"""

source = INSTALLER.read_text(encoding="utf-8")
if source.count(OLD) != 1:
    raise SystemExit("refusing materialization: exact #2949 startup fence precondition changed")
INSTALLER.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")
