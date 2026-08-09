#!/usr/bin/env python3
"""Execute the pinned ES80 TODAY candidate crosscheck under producer-owned custody.

A caller-written PASS_NOT_FINAL_GO JSON document is not independent evidence. This module resolves
one reviewed crosscheck Git blob from one pinned tooling commit, independently verifies the blob
bytes, snapshots them into a private directory, and executes those exact bytes with an isolated
Python interpreter against the retained candidate. The resulting JSON is the authority consumed by
the canonical Final GO composer; a supplied receipt is continuity material only.

This module does not inspect Apple code signing, authorize physical Experiment One, create scooter
telemetry, or grant Bluetooth write/command authority.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
from typing import Any

PINNED_CROSSCHECK_COMMIT = "d827a296048386bda62024ea3278775d5344c47c"
PINNED_CROSSCHECK_BLOB = "c3b2b620280484c05316fc5c2fa2ca451f1fdc83"
CROSSCHECK_PATH = "scripts/ci/es80_today_independent_candidate_crosscheck.py"
HEX40 = re.compile(r"^[0-9a-f]{40}$")


class TrustedCrosscheckExecutionError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TrustedCrosscheckExecutionError(message)


def _closed_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }


def _real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise TrustedCrosscheckExecutionError(f"{label} is unavailable: {path}") from error
    if path.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise TrustedCrosscheckExecutionError(f"{label} must be one real non-symlink directory")
    return path.resolve(strict=True)


def _git(repository: Path, *arguments: str, binary: bool = False) -> bytes | str:
    repository = _real_directory(repository, "tooling repository")
    try:
        raw = subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            env=_closed_git_environment(),
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise TrustedCrosscheckExecutionError(
            f"trusted crosscheck Git lookup failed: {' '.join(arguments)}"
        ) from error
    if binary:
        return raw
    try:
        return raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise TrustedCrosscheckExecutionError("trusted crosscheck Git text was not UTF-8") from error


def _git_blob_oid(raw: bytes) -> str:
    header = f"blob {len(raw)}\0".encode("ascii")
    return hashlib.sha1(header + raw).hexdigest()


def pinned_crosscheck_bytes(tooling_repo: Path) -> bytes:
    """Return exact reviewed crosscheck bytes after commit/path/object verification."""
    commit = _git(tooling_repo, "rev-parse", "--verify", f"{PINNED_CROSSCHECK_COMMIT}^{{commit}}")
    _require(commit == PINNED_CROSSCHECK_COMMIT, "pinned crosscheck tooling commit is unavailable")
    blob = _git(tooling_repo, "rev-parse", f"{PINNED_CROSSCHECK_COMMIT}:{CROSSCHECK_PATH}")
    _require(blob == PINNED_CROSSCHECK_BLOB, "pinned crosscheck path does not resolve reviewed blob")
    raw = _git(tooling_repo, "cat-file", "blob", PINNED_CROSSCHECK_BLOB, binary=True)
    assert isinstance(raw, bytes)
    _require(
        _git_blob_oid(raw) == PINNED_CROSSCHECK_BLOB,
        "pinned crosscheck object bytes do not reproduce reviewed Git blob identity",
    )
    return raw


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise TrustedCrosscheckExecutionError(
                f"trusted crosscheck output contains duplicate key: {key}"
            )
        value[key] = item
    return value


def _parse_receipt(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw, object_pairs_hook=_reject_duplicate_pairs)
    except TrustedCrosscheckExecutionError:
        raise
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise TrustedCrosscheckExecutionError("trusted crosscheck output is not valid UTF-8 JSON") from error
    _require(isinstance(value, dict), "trusted crosscheck output must be one JSON object")
    return value


def execute_trusted_crosscheck(
    *,
    tooling_repo: Path,
    candidate_dir: Path,
    expected_source_sha: str,
) -> tuple[bytes, dict[str, Any]]:
    """Execute exact pinned producer bytes and return canonical receipt bytes + parsed object."""
    _require(
        isinstance(expected_source_sha, str) and HEX40.fullmatch(expected_source_sha) is not None,
        "expected candidate source SHA must be one lowercase 40-hex commit",
    )
    candidate = _real_directory(candidate_dir, "retained candidate directory")
    producer = pinned_crosscheck_bytes(tooling_repo)

    with tempfile.TemporaryDirectory(prefix="nembra-final-go-crosscheck-") as temporary:
        private_root = Path(temporary)
        private_root.chmod(0o700)
        snapshot = private_root / "trusted-crosscheck.py"
        descriptor = os.open(snapshot, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            offset = 0
            while offset < len(producer):
                written = os.write(descriptor, producer[offset:])
                if written <= 0:
                    raise OSError("short write while snapshotting trusted crosscheck producer")
                offset += written
            os.fsync(descriptor)
        finally:
            os.close(descriptor)

        _require(snapshot.read_bytes() == producer, "trusted crosscheck private snapshot bytes changed")
        environment = {
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": str(private_root),
            "LC_ALL": "C",
            "PYTHONNOUSERSITE": "1",
        }
        try:
            completed = subprocess.run(
                [
                    "/usr/bin/python3",
                    "-I",
                    str(snapshot),
                    "--candidate-dir",
                    str(candidate),
                    "--expected-source-sha",
                    expected_source_sha,
                ],
                cwd=private_root,
                env=environment,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise TrustedCrosscheckExecutionError("trusted crosscheck producer could not execute") from error

        if completed.returncode != 0:
            diagnostic = completed.stderr.decode("utf-8", errors="replace").strip()
            if len(diagnostic) > 600:
                diagnostic = diagnostic[:600] + "…"
            raise TrustedCrosscheckExecutionError(
                "trusted crosscheck producer rejected retained candidate"
                + (f": {diagnostic}" if diagnostic else "")
            )

        record = _parse_receipt(completed.stdout)
        canonical = (json.dumps(record, indent=2, sort_keys=True) + "\n").encode("utf-8")
        _require(
            completed.stdout == canonical,
            "trusted crosscheck producer output is not canonical deterministic JSON",
        )
        return canonical, record
