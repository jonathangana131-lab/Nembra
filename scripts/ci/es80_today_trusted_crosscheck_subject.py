#!/usr/bin/env python3
"""Bind Final GO crosscheck authority to execution of the pinned independent producer.

The retained crosscheck JSON is a handoff copy, not authority by itself.  Final GO obtains the
reviewed crosscheck source from its exact pinned Git object, executes those exact bytes under
isolated Python against the exact candidate, and requires the supplied handoff receipt to be
byte-identical to that trusted execution output.

This is software evidence only.  It does not authenticate Apple signing by itself, prove device
installation/runtime state, authorize Bluetooth writes, or create physical ES80 truth.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
from typing import Any

PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
CROSSCHECK_AUTHORITY = "independent-retained-candidate-evidence-crosscheck-not-final-go"
TRUSTED_EXECUTION_AUTHORITY = "final-go-pinned-crosscheck-execution-v1"

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")


class TrustedCrosscheckError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TrustedCrosscheckError(message)


def _closed_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }


def _closed_python_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "PYTHONNOUSERSITE": "1",
    }


def _real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise TrustedCrosscheckError(f"{label} is unavailable: {path}") from error
    _require(not path.is_symlink() and stat.S_ISDIR(metadata.st_mode), f"{label} must be one real directory")
    return path.absolute()


def _regular_bytes(path: Path, label: str) -> bytes:
    try:
        before = path.lstat()
    except OSError as error:
        raise TrustedCrosscheckError(f"{label} is unavailable: {path}") from error
    _require(
        not path.is_symlink() and stat.S_ISREG(before.st_mode) and before.st_size > 0,
        f"{label} must be one non-empty regular non-symlink file",
    )
    try:
        raw = path.read_bytes()
        after = path.lstat()
    except OSError as error:
        raise TrustedCrosscheckError(f"{label} is unreadable: {path}") from error
    _require(
        before.st_dev == after.st_dev
        and before.st_ino == after.st_ino
        and before.st_size == after.st_size
        and len(raw) == after.st_size,
        f"{label} changed while reading",
    )
    return raw


def _git_bytes(repository: Path, *arguments: str, input_bytes: bytes | None = None) -> bytes:
    repository = _real_directory(repository, "tooling repository")
    try:
        result = subprocess.run(
            ["/usr/bin/git", *arguments],
            cwd=repository,
            env=_closed_git_environment(),
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise TrustedCrosscheckError("closed Git operation failed") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise TrustedCrosscheckError(f"closed Git operation rejected pinned crosscheck authority: {detail}")
    return result.stdout


def _git_text(repository: Path, *arguments: str) -> str:
    try:
        value = _git_bytes(repository, *arguments).decode("ascii").strip().lower()
    except UnicodeDecodeError as error:
        raise TrustedCrosscheckError("Git object identity was not ASCII") from error
    return value


def _pinned_tool_bytes(tooling_repo: Path) -> bytes:
    commit = _git_text(tooling_repo, "rev-parse", "--verify", f"{PINNED_CROSSCHECK_COMMIT}^{{commit}}")
    _require(commit == PINNED_CROSSCHECK_COMMIT, "pinned crosscheck commit is unavailable or aliases another commit")

    blob = _git_text(tooling_repo, "rev-parse", f"{PINNED_CROSSCHECK_COMMIT}:{PINNED_CROSSCHECK_PATH}")
    _require(_GIT_OID.fullmatch(blob) is not None, "pinned crosscheck Git blob identity is malformed")
    _require(blob == PINNED_CROSSCHECK_BLOB, "pinned crosscheck Git blob is not accepted authority")

    source = _git_bytes(tooling_repo, "cat-file", "blob", PINNED_CROSSCHECK_BLOB)
    _require(source, "pinned crosscheck Git blob is empty")
    rehashed = _git_bytes(tooling_repo, "hash-object", "--stdin", input_bytes=source).decode("ascii").strip().lower()
    _require(rehashed == PINNED_CROSSCHECK_BLOB, "pinned crosscheck bytes do not reproduce the accepted Git blob")
    return source


def _execute_pinned_tool(tool_bytes: bytes, candidate_root: Path, expected_source_sha: str) -> bytes:
    _require(_HEX40.fullmatch(expected_source_sha) is not None, "expected source SHA is not canonical lowercase 40-hex")
    candidate = _real_directory(candidate_root, "retained candidate directory")
    command = [
        "/usr/bin/python3",
        "-I",
        "-",
        "--candidate-dir",
        str(candidate),
        "--expected-source-sha",
        expected_source_sha,
    ]
    try:
        result = subprocess.run(
            command,
            cwd=Path("/"),
            env=_closed_python_environment(),
            input=tool_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise TrustedCrosscheckError("pinned crosscheck execution failed") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise TrustedCrosscheckError(f"pinned crosscheck execution rejected retained candidate: {detail}")
    _require(result.stdout, "pinned crosscheck execution produced no receipt")
    _require(not result.stderr.strip(), "pinned crosscheck execution emitted unexpected stderr")
    return result.stdout


def _strict_json_object(raw: bytes) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise TrustedCrosscheckError(f"trusted crosscheck output contains duplicate key: {key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicates)
    except TrustedCrosscheckError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise TrustedCrosscheckError("pinned crosscheck output is not valid UTF-8 JSON") from error
    _require(isinstance(value, dict), "pinned crosscheck output root is not one JSON object")
    return value


def verify_trusted_crosscheck_receipt(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    supplied_receipt_path: Path,
    tooling_repo: Path,
) -> dict[str, Any]:
    """Execute the pinned producer and bind the handoff receipt to its exact stdout bytes."""

    source = expected_source_sha.strip().lower()
    _require(_HEX40.fullmatch(source) is not None, "expected source SHA is not canonical lowercase 40-hex")
    tool_bytes = _pinned_tool_bytes(tooling_repo)
    produced = _execute_pinned_tool(tool_bytes, candidate_root, source)
    supplied = _regular_bytes(supplied_receipt_path, "independent crosscheck handoff receipt")
    _require(
        supplied == produced,
        "independent crosscheck handoff receipt is not byte-identical to trusted pinned-producer execution",
    )

    receipt = _strict_json_object(produced)
    _require(receipt.get("authority") == CROSSCHECK_AUTHORITY, "trusted crosscheck output authority changed")
    _require(receipt.get("status") == "PASS_NOT_FINAL_GO", "trusted crosscheck output status is not PASS_NOT_FINAL_GO")
    _require(receipt.get("sourceCommitSHA") == source, "trusted crosscheck output source does not match candidate")
    _require(receipt.get("physicalExperimentAuthorization") == "not-granted", "trusted crosscheck output widened physical authority")

    return {
        "authority": TRUSTED_EXECUTION_AUTHORITY,
        "toolCommit": PINNED_CROSSCHECK_COMMIT,
        "toolPath": PINNED_CROSSCHECK_PATH,
        "toolGitBlob": PINNED_CROSSCHECK_BLOB,
        "producerOutputSHA256": hashlib.sha256(produced).hexdigest(),
        "producerOutputByteCount": len(produced),
        "candidateSourceCommitSHA": source,
        "producerStatus": "PASS_NOT_FINAL_GO",
        "physicalExperimentAuthorization": "not-granted",
    }
