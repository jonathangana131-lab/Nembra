#!/usr/bin/env python3
"""Freshly re-inspect the exact retained TODAY signed field candidate before Final GO.

The field producer already owns a strong private-input path: an exact accepted-source private runner
loads the exact accepted-source canonical inspector from an inherited regular-file descriptor, keeps
the intended-device identifier behind an external private mode-0600 file, and lets the inspector
perform real Apple signing/provisioning/device-membership checks on macOS.

Final GO must not trust caller-authored copies of the JSON that producer once emitted. This module
materializes the private runner + inspector from the accepted source Git objects, executes them again
against the exact retained IPA, and requires the retained candidate evidence bytes to match the fresh
inspection exactly. The raw intended-device identifier is never returned, persisted, or printed.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
from typing import Final

REINSPECTION_CUSTODY: Final = "fresh-accepted-source-signed-inspector-v1"
MAX_EVIDENCE_BYTES: Final = 2 * 1024 * 1024
MAX_IPA_BYTES: Final = 2 * 1024 * 1024 * 1024
_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")


class SignedCandidateReinspectionError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SignedCandidateReinspectionError(message)


def _closed_env(home: Path) -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(home),
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
        raise SignedCandidateReinspectionError(f"{label} is unavailable: {expanded}") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SignedCandidateReinspectionError(f"{label} must be one real non-symlink directory")
    try:
        return expanded.resolve(strict=True)
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} cannot be resolved") from error


def _candidate_inspection_root(candidate_root: Path) -> Path:
    candidate = _real_directory(candidate_root, "signed candidate root")
    inspection = candidate / "inspection"
    try:
        metadata = inspection.lstat()
    except OSError as error:
        raise SignedCandidateReinspectionError("signed candidate inspection directory is unavailable") from error
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SignedCandidateReinspectionError(
            "signed candidate inspection directory must be one real non-symlink directory"
        )
    return inspection


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
            env=_closed_env(Path("/tmp")),
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SignedCandidateReinspectionError(
            f"signed-inspector Git lookup failed: {' '.join(arguments)}"
        ) from error


def _git_text(
    repository: Path,
    *arguments: str,
    input_bytes: bytes | None = None,
) -> str:
    completed = _git_process(repository, *arguments, input_bytes=input_bytes)
    if completed.returncode != 0:
        raise SignedCandidateReinspectionError(
            f"signed-inspector Git lookup failed: {' '.join(arguments)}"
        )
    try:
        return completed.stdout.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise SignedCandidateReinspectionError("signed-inspector Git text output is not UTF-8") from error


def _git_bytes(repository: Path, *arguments: str) -> bytes:
    completed = _git_process(repository, *arguments)
    if completed.returncode != 0 or not completed.stdout:
        raise SignedCandidateReinspectionError(
            f"signed-inspector Git object read failed: {' '.join(arguments)}"
        )
    return completed.stdout


def _materialize_source_tool(
    repository: Path,
    source: str,
    relative_path: str,
    label: str,
) -> tuple[bytes, str]:
    _require(relative_path and not relative_path.startswith("/"), f"{label} path is not repository-relative")
    _require(".." not in Path(relative_path).parts, f"{label} path escapes the repository")
    blob = _git_text(repository, "rev-parse", f"{source}:{relative_path}").lower()
    _require(_GIT_OID.fullmatch(blob) is not None, f"{label} Git blob is not canonical")
    raw = _git_bytes(repository, "cat-file", "blob", blob)
    rehashed = _git_text(repository, "hash-object", "--stdin", input_bytes=raw).lower()
    _require(rehashed == blob, f"materialized {label} bytes do not match accepted Git blob")
    return raw, blob


def _stable_identity(metadata: os.stat_result) -> tuple[int, int, int, int, int, int, int, int, int]:
    return (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_nlink,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )


def _open_regular(path: Path, label: str, *, max_bytes: int) -> tuple[int, os.stat_result]:
    expanded = path.expanduser()
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        path_metadata = expanded.lstat()
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} is unavailable") from error
    if stat.S_ISLNK(path_metadata.st_mode) or not stat.S_ISREG(path_metadata.st_mode):
        raise SignedCandidateReinspectionError(f"{label} must be one regular non-symlink file")
    if path_metadata.st_size <= 0 or path_metadata.st_size > max_bytes:
        raise SignedCandidateReinspectionError(f"{label} byte count is outside the accepted bound")
    try:
        descriptor = os.open(expanded, flags)
    except OSError as error:
        raise SignedCandidateReinspectionError(f"{label} could not be opened safely") from error
    metadata = os.fstat(descriptor)
    if (
        not stat.S_ISREG(metadata.st_mode)
        or metadata.st_size <= 0
        or metadata.st_size > max_bytes
        or path_metadata.st_dev != metadata.st_dev
        or path_metadata.st_ino != metadata.st_ino
    ):
        os.close(descriptor)
        raise SignedCandidateReinspectionError(f"{label} pathname did not admit one stable regular file")
    return descriptor, metadata


def _read_regular_exact(path: Path, label: str, *, max_bytes: int = MAX_EVIDENCE_BYTES) -> bytes:
    descriptor, before = _open_regular(path, label, max_bytes=max_bytes)
    try:
        chunks: list[bytes] = []
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(65536, remaining))
            if not chunk:
                raise SignedCandidateReinspectionError(f"{label} changed during descriptor read")
            chunks.append(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise SignedCandidateReinspectionError(f"{label} grew during descriptor read")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if _stable_identity(before) != _stable_identity(after):
        raise SignedCandidateReinspectionError(f"{label} identity changed during descriptor read")
    raw = b"".join(chunks)
    if len(raw) != before.st_size:
        raise SignedCandidateReinspectionError(f"{label} byte count changed during descriptor read")
    return raw


def _sha_regular_exact(path: Path, label: str) -> tuple[str, int]:
    descriptor, before = _open_regular(path, label, max_bytes=MAX_IPA_BYTES)
    digest = hashlib.sha256()
    try:
        remaining = before.st_size
        while remaining:
            chunk = os.read(descriptor, min(1024 * 1024, remaining))
            if not chunk:
                raise SignedCandidateReinspectionError(f"{label} changed during descriptor hash")
            digest.update(chunk)
            remaining -= len(chunk)
        if os.read(descriptor, 1):
            raise SignedCandidateReinspectionError(f"{label} grew during descriptor hash")
        after = os.fstat(descriptor)
    finally:
        os.close(descriptor)
    if _stable_identity(before) != _stable_identity(after):
        raise SignedCandidateReinspectionError(f"{label} identity changed during descriptor hash")
    return digest.hexdigest(), before.st_size


def _run_private_inspector(
    *,
    runner_bytes: bytes,
    inspector_bytes: bytes,
    ipa_path: Path,
    output_dir: Path,
    expected_source_sha: str,
    intended_device_udid_file: Path,
    repository_root: Path,
) -> None:
    """Execute accepted-source runner bytes while passing inspector bytes only by inherited FD."""
    with tempfile.TemporaryFile(prefix="nembra-final-go-inspector-", mode="w+b") as inspector_file:
        inspector_file.write(inspector_bytes)
        inspector_file.flush()
        inspector_file.seek(0)
        descriptor = inspector_file.fileno()
        try:
            completed = subprocess.run(
                [
                    "/usr/bin/python3",
                    "-I",
                    "-",
                    "--ipa",
                    str(ipa_path),
                    "--output-dir",
                    str(output_dir),
                    "--expected-source-sha",
                    expected_source_sha,
                    "--intended-device-udid-file",
                    str(intended_device_udid_file),
                    "--repository-root",
                    str(repository_root),
                    "--canonical-inspector-fd",
                    str(descriptor),
                ],
                input=runner_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=_closed_env(output_dir.parent),
                cwd="/",
                pass_fds=(descriptor,),
                check=False,
                timeout=180,
            )
        except (OSError, subprocess.TimeoutExpired) as error:
            raise SignedCandidateReinspectionError("accepted-source signed-field inspector could not execute") from error
    if completed.returncode != 0:
        # The accepted private runner deliberately redacts inspector diagnostics so the private
        # identifier cannot leak. Keep our wrapper equally bounded and never render argv.
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        suffix = f": {detail[:512]}" if detail else ""
        raise SignedCandidateReinspectionError(
            f"accepted-source signed-field reinspection rejected the retained candidate{suffix}"
        )


def verify_signed_candidate_reinspection(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    frozen_source_repo: Path,
    private_runner_path: str,
    inspector_path: str,
    intended_device_udid_file: Path,
) -> dict[str, str | int]:
    """Require retained candidate evidence to equal one fresh accepted-source Apple inspection."""
    _require(_HEX40.fullmatch(expected_source_sha) is not None, "expected source SHA is not canonical")
    repository = _real_directory(frozen_source_repo, "frozen source repository")
    resolved = _git_text(repository, "rev-parse", "--verify", f"{expected_source_sha}^{{commit}}").lower()
    _require(resolved == expected_source_sha, "frozen source repository did not resolve exact accepted source")

    runner_bytes, runner_blob = _materialize_source_tool(
        repository,
        expected_source_sha,
        private_runner_path,
        "private signed-field runner",
    )
    inspector_bytes, inspector_blob = _materialize_source_tool(
        repository,
        expected_source_sha,
        inspector_path,
        "canonical signed-field inspector",
    )

    supplied_root = _candidate_inspection_root(candidate_root)
    supplied_ipa = supplied_root / "build-evidence" / "NembraField.ipa"
    udid_path = intended_device_udid_file.expanduser()
    _require(udid_path.is_absolute(), "intended-device verification file path must be absolute")

    with tempfile.TemporaryDirectory(prefix="nembra-final-go-fresh-signed-inspection-") as temporary:
        fresh_root = Path(temporary) / "inspection"
        _run_private_inspector(
            runner_bytes=runner_bytes,
            inspector_bytes=inspector_bytes,
            ipa_path=supplied_ipa,
            output_dir=fresh_root,
            expected_source_sha=expected_source_sha,
            intended_device_udid_file=udid_path,
            repository_root=repository,
        )

        pairs = (
            ("NembraCaptureExternalBuildRecord.json", "external build record"),
            ("NembraCaptureFieldBuildEvidenceRecord.json", "field-build evidence record"),
            ("NembraCaptureSignedFieldArtifactInspection.json", "signed artifact inspection"),
        )
        digests: dict[str, str] = {}
        digest_keys = (
            "externalBuildRecordSHA256",
            "fieldBuildEvidenceRecordSHA256",
            "signedArtifactInspectionSHA256",
        )
        for (filename, label), digest_key in zip(pairs, digest_keys, strict=True):
            supplied = _read_regular_exact(supplied_root / filename, f"retained {label}")
            fresh = _read_regular_exact(fresh_root / filename, f"fresh {label}")
            _require(supplied == fresh, f"retained {label} is not exact fresh accepted-source inspector output")
            digests[digest_key] = hashlib.sha256(supplied).hexdigest()

        supplied_ipa_sha, supplied_ipa_size = _sha_regular_exact(supplied_ipa, "retained signed IPA")
        fresh_ipa_sha, fresh_ipa_size = _sha_regular_exact(
            fresh_root / "build-evidence" / "NembraField.ipa",
            "fresh reinspection retained IPA",
        )
        _require(
            supplied_ipa_sha == fresh_ipa_sha and supplied_ipa_size == fresh_ipa_size,
            "fresh signed-field inspector did not retain the exact candidate IPA subject",
        )

    return {
        "executionCustody": REINSPECTION_CUSTODY,
        "inspectorSourceCommitSHA": expected_source_sha,
        "privateRunnerGitBlob": runner_blob,
        "canonicalInspectorGitBlob": inspector_blob,
        "retainedIPASHA256": supplied_ipa_sha,
        "retainedIPAByteCount": supplied_ipa_size,
        **digests,
    }
