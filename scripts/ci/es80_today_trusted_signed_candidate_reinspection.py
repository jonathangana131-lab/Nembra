#!/usr/bin/env python3
"""Freshly re-inspect one retained signed field IPA under reviewed producer custody.

Final GO must not promote caller-authored Apple signing/provisioning JSON into machine evidence.
This module materializes the exact reviewed private runner and canonical inspector Git blobs from
one accepted source commit, binds both subjects to already-open descriptors, removes their mutable
pathnames, and runs the runner with isolated system Python against the exact retained candidate IPA.

The intended-device identifier remains verification-only private input: this module accepts only the
path to the existing private mode-0600 value file and never places the raw identifier in argv,
environment, artifacts, or diagnostics. The fresh evidence directory is private and temporary.

This is evidence verification only. It does not authorize physical Experiment One, Bluetooth
writes, commands, scooter identity, protocol semantics, or telemetry.
"""
from __future__ import annotations

from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Iterator

PRIVATE_RUNNER_PATH = "scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_RUNNER_BLOB = "f648b3080313f65da1e358ef3beb8c23d05966e6"
INSPECTOR_PATH = "scripts/ci/es80_signed_field_artifact_evidence.py"
INSPECTOR_BLOB = "57ec5f42b23ade83f1367fa86fe8f60f2144f241"
IPA_RELATIVE_PATH = Path("inspection/build-evidence/NembraField.ipa")
PYTHON3 = Path("/usr/bin/python3")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
MAX_TOOL_BYTES = 2 * 1024 * 1024


class TrustedSignedCandidateReinspectionError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TrustedSignedCandidateReinspectionError(message)


def _closed_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": "/tmp",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
    }


def _closed_python_environment(home: Path) -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(home),
        "LC_ALL": "C",
        "PYTHONNOUSERSITE": "1",
    }


def _real_directory(path: Path, label: str) -> Path:
    candidate = path.expanduser()
    try:
        metadata = candidate.lstat()
    except OSError as error:
        raise TrustedSignedCandidateReinspectionError(f"{label} is unavailable: {candidate}") from error
    if candidate.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise TrustedSignedCandidateReinspectionError(
            f"{label} must be one real non-symlink directory: {candidate}"
        )
    try:
        return candidate.resolve(strict=True)
    except OSError as error:
        raise TrustedSignedCandidateReinspectionError(f"{label} could not be resolved") from error


def _git(repository: Path, *arguments: str, binary: bool = False) -> bytes | str:
    repository = _real_directory(repository, "frozen source repository")
    try:
        raw = subprocess.check_output(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            env=_closed_git_environment(),
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise TrustedSignedCandidateReinspectionError(
            f"trusted signed-candidate Git lookup failed: {' '.join(arguments)}"
        ) from error
    if binary:
        return raw
    try:
        return raw.decode("utf-8").strip()
    except UnicodeDecodeError as error:
        raise TrustedSignedCandidateReinspectionError(
            "trusted signed-candidate Git text was not UTF-8"
        ) from error


def _git_blob_oid(raw: bytes, expected: str) -> str:
    if len(expected) == 40:
        digest = hashlib.sha1()
    elif len(expected) == 64:
        digest = hashlib.sha256()
    else:
        raise TrustedSignedCandidateReinspectionError("unsupported reviewed Git object ID width")
    digest.update(f"blob {len(raw)}\0".encode("ascii"))
    digest.update(raw)
    return digest.hexdigest()


def _pinned_blob_bytes(repository: Path, source: str, path: str, expected_blob: str) -> bytes:
    resolved = _git(repository, "rev-parse", f"{source}:{path}")
    _require(resolved == expected_blob, f"reviewed signed-candidate tool blob drifted: {path}")
    raw = _git(repository, "cat-file", "blob", expected_blob, binary=True)
    assert isinstance(raw, bytes)
    _require(0 < len(raw) <= MAX_TOOL_BYTES, f"reviewed signed-candidate tool has invalid size: {path}")
    _require(
        _git_blob_oid(raw, expected_blob) == expected_blob,
        f"reviewed signed-candidate Git object bytes do not reproduce blob identity: {path}",
    )
    return raw


def reviewed_tool_bytes(repository: Path, source_commit_sha: str) -> tuple[bytes, bytes]:
    """Resolve both reviewed tool subjects from one exact accepted source commit."""
    _require(
        isinstance(source_commit_sha, str) and HEX40.fullmatch(source_commit_sha) is not None,
        "accepted source SHA must be one canonical lowercase 40-hex commit",
    )
    resolved_commit = _git(repository, "rev-parse", "--verify", f"{source_commit_sha}^{{commit}}")
    _require(resolved_commit == source_commit_sha, "accepted source commit is unavailable in frozen repository")
    runner = _pinned_blob_bytes(repository, source_commit_sha, PRIVATE_RUNNER_PATH, PRIVATE_RUNNER_BLOB)
    inspector = _pinned_blob_bytes(repository, source_commit_sha, INSPECTOR_PATH, INSPECTOR_BLOB)
    return runner, inspector


def _write_private_tool(path: Path, raw: bytes) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    try:
        offset = 0
        while offset < len(raw):
            written = os.write(descriptor, raw[offset:])
            if written <= 0:
                raise OSError("short write while snapshotting reviewed signed-candidate tool")
            offset += written
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _descriptor_blob_identity(descriptor: int, expected_blob: str, expected_size: int) -> None:
    metadata = os.fstat(descriptor)
    _require(stat.S_ISREG(metadata.st_mode), "reviewed signed-candidate tool descriptor is not regular")
    _require(metadata.st_size == expected_size, "reviewed signed-candidate tool descriptor size drifted")
    before = (
        metadata.st_dev,
        metadata.st_ino,
        metadata.st_mode,
        metadata.st_uid,
        metadata.st_gid,
        metadata.st_size,
        metadata.st_mtime_ns,
        metadata.st_ctime_ns,
    )
    raw = bytearray()
    offset = 0
    while offset < expected_size:
        chunk = os.pread(descriptor, min(1024 * 1024, expected_size - offset), offset)
        if not chunk:
            break
        raw.extend(chunk)
        offset += len(chunk)
    _require(len(raw) == expected_size, "reviewed signed-candidate tool descriptor ended early")
    _require(not os.pread(descriptor, 1, expected_size), "reviewed signed-candidate tool descriptor grew")
    after_metadata = os.fstat(descriptor)
    after = (
        after_metadata.st_dev,
        after_metadata.st_ino,
        after_metadata.st_mode,
        after_metadata.st_uid,
        after_metadata.st_gid,
        after_metadata.st_size,
        after_metadata.st_mtime_ns,
        after_metadata.st_ctime_ns,
    )
    _require(before == after, "reviewed signed-candidate tool descriptor changed during verification")
    _require(
        _git_blob_oid(bytes(raw), expected_blob) == expected_blob,
        "reviewed signed-candidate open descriptor does not match Git blob identity",
    )


def _trusted_python() -> Path:
    if sys.platform != "darwin":
        raise TrustedSignedCandidateReinspectionError(
            "fresh Apple signing/provisioning reinspection requires macOS"
        )
    try:
        metadata = PYTHON3.lstat()
    except OSError as error:
        raise TrustedSignedCandidateReinspectionError(
            "root-custodied system Python 3 is unavailable"
        ) from error
    if PYTHON3.is_symlink() or not stat.S_ISREG(metadata.st_mode) or not (metadata.st_mode & stat.S_IXUSR):
        raise TrustedSignedCandidateReinspectionError(
            "system Python 3 must be one executable regular non-symlink file"
        )
    if metadata.st_uid != 0 or metadata.st_mode & 0o022:
        raise TrustedSignedCandidateReinspectionError(
            "system Python 3 must be root-owned and not group/world writable"
        )
    return PYTHON3


def _candidate_ipa(candidate_root: Path) -> Path:
    root = _real_directory(candidate_root, "retained signed candidate root")
    inspection = root / "inspection"
    try:
        metadata = inspection.lstat()
    except OSError as error:
        raise TrustedSignedCandidateReinspectionError("retained signed-candidate inspection directory is missing") from error
    if inspection.is_symlink() or not stat.S_ISDIR(metadata.st_mode):
        raise TrustedSignedCandidateReinspectionError(
            "retained signed-candidate inspection directory must be real and non-symlink"
        )
    ipa = inspection / Path("build-evidence/NembraField.ipa")
    try:
        ipa_metadata = ipa.lstat()
    except OSError as error:
        raise TrustedSignedCandidateReinspectionError("retained signed candidate IPA is missing") from error
    if ipa.is_symlink() or not stat.S_ISREG(ipa_metadata.st_mode) or ipa_metadata.st_size <= 0:
        raise TrustedSignedCandidateReinspectionError(
            "retained signed candidate IPA must be one non-empty regular non-symlink file"
        )
    return ipa.resolve(strict=True)


@contextmanager
def trusted_reinspection_candidate_root(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    frozen_source_repo: Path,
    intended_device_udid_file: Path,
    timeout_seconds: int = 180,
) -> Iterator[Path]:
    """Yield a private candidate root whose inspection bytes come from fresh reviewed Apple inspection.

    The yielded root contains exactly the canonical `inspection/` layout expected by Final GO. It is
    removed automatically after the caller consumes it.
    """
    _require(timeout_seconds > 0, "trusted signed-candidate reinspection timeout must be positive")
    source_repo = _real_directory(frozen_source_repo, "frozen source repository")
    runner_raw, inspector_raw = reviewed_tool_bytes(source_repo, expected_source_sha)
    ipa = _candidate_ipa(candidate_root)
    python = _trusted_python()

    with tempfile.TemporaryDirectory(prefix="nembra-final-go-signed-reinspection-") as temporary:
        private_root = Path(temporary)
        private_root.chmod(0o700)
        tool_root = private_root / "tooling"
        tool_root.mkdir(mode=0o700)
        runner_path = tool_root / "private-runner.py"
        inspector_path = tool_root / "canonical-inspector.py"
        _write_private_tool(runner_path, runner_raw)
        _write_private_tool(inspector_path, inspector_raw)

        runner_fd = os.open(runner_path, os.O_RDONLY)
        inspector_fd = os.open(inspector_path, os.O_RDONLY)
        try:
            _descriptor_blob_identity(runner_fd, PRIVATE_RUNNER_BLOB, len(runner_raw))
            _descriptor_blob_identity(inspector_fd, INSPECTOR_BLOB, len(inspector_raw))
            runner_path.unlink()
            inspector_path.unlink()
            tool_root.rmdir()

            fresh_candidate = private_root / "candidate"
            fresh_candidate.mkdir(mode=0o700)
            fresh_inspection = fresh_candidate / "inspection"
            command = [
                str(python),
                "-I",
                f"/dev/fd/{runner_fd}",
                "--ipa",
                str(ipa),
                "--output-dir",
                str(fresh_inspection),
                "--expected-source-sha",
                expected_source_sha,
                "--intended-device-udid-file",
                str(intended_device_udid_file),
                "--repository-root",
                str(source_repo),
                "--canonical-inspector-fd",
                str(inspector_fd),
            ]
            try:
                completed = subprocess.run(
                    command,
                    cwd=private_root,
                    env=_closed_python_environment(private_root),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    pass_fds=(runner_fd, inspector_fd),
                    check=False,
                    timeout=timeout_seconds,
                )
            except (OSError, subprocess.TimeoutExpired) as error:
                raise TrustedSignedCandidateReinspectionError(
                    "reviewed signed-candidate reinspection could not complete"
                ) from error
            if completed.returncode != 0:
                diagnostic = completed.stderr.decode("utf-8", errors="replace").strip()
                if len(diagnostic) > 400:
                    diagnostic = diagnostic[:400] + "…"
                raise TrustedSignedCandidateReinspectionError(
                    "reviewed Apple signing/provisioning reinspection rejected retained IPA"
                    + (f": {diagnostic}" if diagnostic else "")
                )

            required = (
                fresh_inspection / "NembraCaptureExternalBuildRecord.json",
                fresh_inspection / "NembraCaptureFieldBuildEvidenceRecord.json",
                fresh_inspection / "NembraCaptureSignedFieldArtifactInspection.json",
                fresh_inspection / "build-evidence/NembraField.ipa",
            )
            for subject in required:
                try:
                    metadata = subject.lstat()
                except OSError as error:
                    raise TrustedSignedCandidateReinspectionError(
                        f"fresh signed-candidate reinspection omitted required subject: {subject.name}"
                    ) from error
                _require(
                    not subject.is_symlink() and stat.S_ISREG(metadata.st_mode) and metadata.st_size > 0,
                    f"fresh signed-candidate reinspection produced invalid subject: {subject.name}",
                )

            yield fresh_candidate
        finally:
            os.close(inspector_fd)
            os.close(runner_fd)
