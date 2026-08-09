#!/usr/bin/env python3
"""Bind a TODAY crosscheck receipt to fresh execution of the exact pinned verifier Git object.

The private field runbook already requires materializing the independent crosscheck from one pinned
Git commit/blob and writing its stdout to the retained receipt. Final GO must not merely trust a
caller-authored JSON file that *names* those Git objects. This module repeats that operation inside
the canonical hardened authority path and requires exact stdout-byte equality with the supplied
receipt before the foundation may consume it.

This module does not inspect Apple signing, authorize physical Experiment One, or replace the
foundation's semantic receipt validation. It proves only that the exact pinned crosscheck producer
freshly emitted the exact supplied receipt bytes for the exact candidate/source inputs.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
from typing import Final

EXECUTION_CUSTODY: Final = "fresh-pinned-tool-exact-stdout-v1"
MAX_RECEIPT_BYTES: Final = 256 * 1024
_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")


class CrosscheckReceiptCustodyError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CrosscheckReceiptCustodyError(message)


def _closed_env() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "LANG": "C",
        "LC_ALL": "C",
        "PYTHONHASHSEED": "0",
        "PYTHONNOUSERSITE": "1",
    }


def _real_directory(path: Path, label: str) -> Path:
    expanded = path.expanduser()
    try:
        metadata = expanded.lstat()
    except OSError as error:
        raise CrosscheckReceiptCustodyError(f"{label} is unavailable: {expanded}") from error
    if expanded.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise CrosscheckReceiptCustodyError(f"{label} must be one real non-symlink directory")
    try:
        return expanded.resolve(strict=True)
    except OSError as error:
        raise CrosscheckReceiptCustodyError(f"{label} cannot be resolved") from error


def _git_process(
    repository: Path,
    *arguments: str,
    input_bytes: bytes | None = None,
) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_closed_env(),
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CrosscheckReceiptCustodyError(
            f"pinned crosscheck Git lookup failed: {' '.join(arguments)}"
        ) from error


def _git_text(
    repository: Path,
    *arguments: str,
    input_bytes: bytes | None = None,
) -> str:
    completed = _git_process(repository, *arguments, input_bytes=input_bytes)
    if completed.returncode != 0:
        raise CrosscheckReceiptCustodyError(
            f"pinned crosscheck Git lookup failed: {' '.join(arguments)}"
        )
    try:
        return completed.stdout.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise CrosscheckReceiptCustodyError("pinned crosscheck Git text output is not UTF-8") from error


def _git_bytes(repository: Path, *arguments: str) -> bytes:
    completed = _git_process(repository, *arguments)
    if completed.returncode != 0:
        raise CrosscheckReceiptCustodyError(
            f"pinned crosscheck Git object read failed: {' '.join(arguments)}"
        )
    if not completed.stdout:
        raise CrosscheckReceiptCustodyError("pinned crosscheck Git object is empty")
    return completed.stdout


def _read_regular_file_exact(path: Path, label: str, *, max_bytes: int) -> bytes:
    expanded = path.expanduser()
    if not hasattr(os, "O_NOFOLLOW"):
        raise CrosscheckReceiptCustodyError("descriptor-bound crosscheck receipt reads require O_NOFOLLOW support")
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    try:
        before_path = expanded.lstat()
    except OSError as error:
        raise CrosscheckReceiptCustodyError(f"{label} is unavailable") from error
    if stat.S_ISLNK(before_path.st_mode) or not stat.S_ISREG(before_path.st_mode):
        raise CrosscheckReceiptCustodyError(f"{label} must be one regular non-symlink file")
    if before_path.st_size <= 0 or before_path.st_size > max_bytes:
        raise CrosscheckReceiptCustodyError(f"{label} byte count is outside the accepted bound")

    try:
        descriptor = os.open(expanded, flags)
    except OSError as error:
        raise CrosscheckReceiptCustodyError(f"{label} could not be opened safely") from error
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise CrosscheckReceiptCustodyError(f"{label} descriptor is not a regular file")
        if before.st_size <= 0 or before.st_size > max_bytes:
            raise CrosscheckReceiptCustodyError(f"{label} descriptor byte count is outside the accepted bound")
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                raise CrosscheckReceiptCustodyError(f"{label} changed during descriptor read")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise CrosscheckReceiptCustodyError(f"{label} grew during descriptor read")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)

    identity_before = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_uid,
        before.st_gid,
        before.st_size,
        before.st_mtime_ns,
        before.st_ctime_ns,
    )
    identity_after = (
        after.st_dev,
        after.st_ino,
        after.st_mode,
        after.st_uid,
        after.st_gid,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    if identity_before != identity_after:
        raise CrosscheckReceiptCustodyError(f"{label} identity changed during descriptor read")
    if before_path.st_dev != before.st_dev or before_path.st_ino != before.st_ino:
        raise CrosscheckReceiptCustodyError(f"{label} pathname changed before descriptor admission")
    raw = b"".join(chunks)
    if len(raw) != before.st_size:
        raise CrosscheckReceiptCustodyError(f"{label} byte count changed during descriptor read")
    return raw


def _run_pinned_tool(tool_bytes: bytes, candidate_root: Path, expected_source_sha: str) -> bytes:
    candidate = candidate_root.expanduser().absolute()
    try:
        completed = subprocess.run(
            [
                "/usr/bin/python3",
                "-I",
                "-",
                "--candidate-dir",
                str(candidate),
                "--expected-source-sha",
                expected_source_sha,
            ],
            input=tool_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=_closed_env(),
            check=False,
            timeout=60,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise CrosscheckReceiptCustodyError("pinned crosscheck execution failed") from error
    if completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail[:512]}" if detail else ""
        raise CrosscheckReceiptCustodyError(
            f"pinned crosscheck producer rejected the exact candidate{suffix}"
        )
    if not completed.stdout or len(completed.stdout) > MAX_RECEIPT_BYTES:
        raise CrosscheckReceiptCustodyError("pinned crosscheck stdout byte count is outside the accepted bound")
    return completed.stdout


def verify_crosscheck_receipt_custody(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    receipt_path: Path,
    tooling_repo: Path,
    expected_tool_commit: str,
    expected_tool_path: str,
    expected_tool_blob: str,
) -> dict[str, str]:
    """Require the supplied receipt to be exact fresh stdout from the exact pinned Git object."""
    _require(_HEX40.fullmatch(expected_source_sha) is not None, "expected source SHA is not canonical")
    _require(_HEX40.fullmatch(expected_tool_commit) is not None, "pinned crosscheck commit is not canonical")
    _require(_GIT_OID.fullmatch(expected_tool_blob) is not None, "pinned crosscheck blob is not canonical")
    _require(
        expected_tool_path and not expected_tool_path.startswith("/") and ".." not in Path(expected_tool_path).parts,
        "pinned crosscheck path is not repository-relative",
    )

    repository = _real_directory(tooling_repo, "crosscheck tooling repository")
    resolved_commit = _git_text(
        repository,
        "rev-parse",
        "--verify",
        f"{expected_tool_commit}^{{commit}}",
    ).lower()
    _require(resolved_commit == expected_tool_commit, "pinned crosscheck tooling commit mismatch")

    resolved_blob = _git_text(
        repository,
        "rev-parse",
        f"{expected_tool_commit}:{expected_tool_path}",
    ).lower()
    _require(resolved_blob == expected_tool_blob, "pinned crosscheck tool path resolved to a different blob")

    tool_bytes = _git_bytes(repository, "cat-file", "blob", expected_tool_blob)
    rehashed_blob = _git_text(
        repository,
        "hash-object",
        "--stdin",
        input_bytes=tool_bytes,
    ).lower()
    _require(rehashed_blob == expected_tool_blob, "materialized pinned crosscheck bytes do not match the pinned blob")

    fresh_stdout = _run_pinned_tool(tool_bytes, candidate_root, expected_source_sha)
    supplied = _read_regular_file_exact(
        receipt_path,
        "independent retained-candidate crosscheck receipt",
        max_bytes=MAX_RECEIPT_BYTES,
    )
    _require(
        supplied == fresh_stdout,
        "independent crosscheck receipt is not exact fresh stdout from the pinned verifier",
    )

    return {
        "executionCustody": EXECUTION_CUSTODY,
        "toolCommit": expected_tool_commit,
        "toolGitBlob": expected_tool_blob,
        "receiptSHA256": hashlib.sha256(supplied).hexdigest(),
    }
