#!/usr/bin/env python3
"""Prove a retained TODAY crosscheck receipt came from the exact pinned producer.

Final GO must not promote caller-authored PASS JSON merely because it repeats the expected Git blob
names. This module re-executes the independently pinned crosscheck source directly from its Git blob
under isolated system Python and requires the retained receipt bytes to equal that producer's
deterministic stdout exactly.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
from typing import Callable

PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
CROSSCHECK_PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"
HEX40 = re.compile(r"^[0-9a-f]{40}$")
GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SYSTEM_PYTHON = Path("/usr/bin/python3")


class CrosscheckExecutionError(RuntimeError):
    pass


def _regular_bytes(path: Path, label: str) -> bytes:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise CrosscheckExecutionError(f"{label} is unavailable") from error
    if path.is_symlink() or not stat.S_ISREG(metadata.st_mode) or metadata.st_size <= 0:
        raise CrosscheckExecutionError(f"{label} must be one non-empty regular non-symlink file")
    try:
        raw = path.read_bytes()
    except OSError as error:
        raise CrosscheckExecutionError(f"{label} is unreadable") from error
    if len(raw) != metadata.st_size:
        raise CrosscheckExecutionError(f"{label} byte count changed while reading")
    return raw


def verify_pinned_crosscheck_execution(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    retained_receipt: Path,
    tooling_repo: Path,
    git: Callable[..., str],
    runner: Callable[..., subprocess.CompletedProcess[bytes]] = subprocess.run,
) -> dict[str, str | int]:
    if HEX40.fullmatch(expected_source_sha) is None:
        raise CrosscheckExecutionError("expected source SHA is not canonical")

    commit = git(
        tooling_repo,
        "rev-parse",
        "--verify",
        f"{PINNED_CROSSCHECK_COMMIT}^{{commit}}",
    )
    if commit != PINNED_CROSSCHECK_COMMIT:
        raise CrosscheckExecutionError("pinned crosscheck tooling commit is unavailable")
    blob = git(tooling_repo, "rev-parse", f"{PINNED_CROSSCHECK_COMMIT}:{CROSSCHECK_PATH}")
    if not isinstance(blob, str) or GIT_OID.fullmatch(blob) is None or blob != PINNED_CROSSCHECK_BLOB:
        raise CrosscheckExecutionError("pinned crosscheck tool Git blob changed")

    source = git(tooling_repo, "show", f"{PINNED_CROSSCHECK_COMMIT}:{CROSSCHECK_PATH}")
    if not isinstance(source, str) or not source.strip() or "\x00" in source:
        raise CrosscheckExecutionError("pinned crosscheck source is unavailable")
    source_bytes = (source + ("" if source.endswith("\n") else "\n")).encode("utf-8")

    receipt_bytes = _regular_bytes(retained_receipt, "retained crosscheck receipt")
    try:
        candidate = candidate_root.expanduser().resolve(strict=True)
        python = SYSTEM_PYTHON.resolve(strict=True)
    except OSError as error:
        raise CrosscheckExecutionError("crosscheck execution custody is unavailable") from error

    env = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "PYTHONNOUSERSITE": "1",
        "PYTHONDONTWRITEBYTECODE": "1",
    }
    try:
        completed = runner(
            [
                str(python),
                "-I",
                "-B",
                "-",
                "--candidate-dir",
                str(candidate),
                "--expected-source-sha",
                expected_source_sha,
            ],
            input=source_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CrosscheckExecutionError("pinned crosscheck producer could not execute") from error

    if completed.returncode != 0:
        raise CrosscheckExecutionError(
            f"pinned crosscheck producer rejected the retained candidate (exit {completed.returncode})"
        )
    if completed.stderr:
        raise CrosscheckExecutionError("pinned crosscheck producer emitted unexpected stderr")
    if completed.stdout != receipt_bytes:
        raise CrosscheckExecutionError(
            "retained crosscheck receipt bytes were not emitted by the pinned producer for this candidate"
        )

    return {
        "authority": "pinned-git-blob-reexecution-exact-receipt-bytes",
        "toolCommit": PINNED_CROSSCHECK_COMMIT,
        "toolGitBlob": PINNED_CROSSCHECK_BLOB,
        "receiptSHA256": hashlib.sha256(receipt_bytes).hexdigest(),
        "receiptByteCount": len(receipt_bytes),
        "interpreter": str(python),
        "interpreterMode": "isolated-stdin-source",
    }
