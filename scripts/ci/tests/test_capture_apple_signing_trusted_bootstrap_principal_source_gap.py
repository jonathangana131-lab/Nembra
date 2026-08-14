#!/usr/bin/env python3
"""Portable exact-parent diagnostic for the current trusted-bootstrap principal gap.

GREEN means the pinned #3262 parent is structurally RED: its numeric principal admission and
retirement prove only UID process authority and omit a local user's PrimaryGroupID reference.
This diagnostic is intentionally current-parent-specific. It is not a future repair acceptance
oracle and it never executes sudo/root, Directory Services mutation, signing, Xcode, or devices.
"""
from __future__ import annotations

from pathlib import Path
import sys


EXACT_PARENT = "bf8fd13b0bab33365a306b3fb39988e2dee0f759"
TARGET = Path("scripts/ci/tests/test_capture_apple_signing_trusted_bootstrap_hardening.py")


class DiagnosticError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise DiagnosticError(message)


def section(source: str, start: str, end: str) -> str:
    first = source.find(start)
    require(first >= 0, f"pinned parent shape moved: missing {start!r}")
    last = source.find(end, first + len(start))
    require(last >= 0, f"pinned parent shape moved: missing section end {end!r}")
    return source[first:last]


def main() -> int:
    source = TARGET.read_text(encoding="utf-8")

    process_inventory = section(source, "def numeric_uid_processes", "def direct_ds_numeric_ids")
    require(
        '["/bin/ps", "-axo", "ruid=,uid=,pid=,stat="]' in process_inventory,
        "pinned parent no longer uses the reviewed UID-only process inventory shape; re-review/re-anchor diagnostic",
    )
    require(
        "if ruid == numeric_id or euid == numeric_id" in process_inventory,
        "pinned parent no longer classifies occupancy only by real/effective UID; re-review/re-anchor diagnostic",
    )

    record_admission = section(source, "def identity_records_are_free", "def numeric_identity_is_fresh")
    require(
        'direct_ds_numeric_ids("Users", "UniqueID")' in record_admission,
        "expected current Users/UniqueID admission check moved",
    )
    require(
        'direct_ds_numeric_ids("Groups", "PrimaryGroupID")' in record_admission,
        "expected current Groups/PrimaryGroupID admission check moved",
    )
    require(
        'direct_ds_numeric_ids("Users", "PrimaryGroupID")' not in record_admission,
        "Users/PrimaryGroupID authority is no longer omitted; this current-parent diagnostic must be retired/reviewed",
    )

    freshness = section(source, "def numeric_identity_is_fresh", "def choose_numeric_identity")
    require(
        "return identity_records_are_free(numeric_id) and not numeric_uid_processes(numeric_id)" in freshness,
        "numeric identity freshness no longer has the reviewed records-plus-UID-only shape; re-review/re-anchor diagnostic",
    )

    retirement = section(source, "def retire_numeric_uid_processes", "def ds_record_exists")
    require(
        'for selector in ("-U", "-u")' in retirement,
        "pinned parent UID retirement selectors moved; re-review/re-anchor diagnostic",
    )
    require(
        "numeric_uid_processes(numeric_id)" in retirement,
        "pinned parent no longer proves retirement through the reviewed UID-only process inventory",
    )

    # This source witness deliberately does not prescribe the eventual macOS implementation for
    # saved UID/GID or supplementary-group enumeration. It proves only that the exact parent still
    # has the narrower reviewed authority shape. Real behavioral closure belongs behind an
    # independently trusted privileged executor, not candidate PR bytes.
    print(
        "CAPTURE_SIGNING_PRINCIPAL_SOURCE_PARENT_RED "
        f"parent={EXACT_PARENT} "
        "uidProcessAuthorityOnly=true usersPrimaryGroupIDMissing=true "
        "uidOnlyRetirement=true rootExecuted=false signingAuthorityCreated=false "
        "physicalAuthorityCreated=false"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (DiagnosticError, OSError) as error:
        print(f"CAPTURE_SIGNING_PRINCIPAL_SOURCE_DIAGNOSTIC_REJECTED: {error}", file=sys.stderr)
        raise SystemExit(1)
