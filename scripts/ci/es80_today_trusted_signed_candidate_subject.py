#!/usr/bin/env python3
"""Re-prove one retained TODAY signed-field candidate with frozen Apple inspection tooling.

A caller-written `NembraCaptureSignedFieldArtifactInspection.json` is not Apple signing authority.
For Final GO, the exact retained IPA must be re-inspected on macOS by the exact frozen #833 private
runner + canonical inspector.  Those source bytes are loaded from pinned Git objects, the intended
field-device identifier stays behind the existing external mode-0600 file boundary, and the freshly
produced evidence must be byte-identical to the retained candidate handoff before it can be consumed
by the Final GO semantic validator.

This module does not authorize physical Experiment One.  It produces one trusted *software*
reinspection subject and a temporary trusted candidate root for semantic validation.  Simulator,
Ubuntu, caller JSON, and source-blob identity alone cannot satisfy the production path.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
from typing import Any, Callable, TypeVar

FROZEN_CAPTURE_SOURCE_COMMIT = "f4cd76e301334ce96824d0b150ef03d2d2cb606b"
PRIVATE_RUNNER_PATH = "scripts/ci/es80_signed_field_artifact_private_runner.py"
PRIVATE_RUNNER_BLOB = "f648b3080313f65da1e358ef3beb8c23d05966e6"
INSPECTOR_PATH = "scripts/ci/es80_signed_field_artifact_evidence.py"
INSPECTOR_BLOB = "57ec5f42b23ade83f1367fa86fe8f60f2144f241"
TRUSTED_REINSPECTION_AUTHORITY = "final-go-frozen-apple-reinspection-v1"

EXTERNAL_RECORD_NAME = "NembraCaptureExternalBuildRecord.json"
FIELD_RECORD_NAME = "NembraCaptureFieldBuildEvidenceRecord.json"
INSPECTION_NAME = "NembraCaptureSignedFieldArtifactInspection.json"
IPA_RELATIVE_PATH = Path("build-evidence/NembraField.ipa")
RETAINED_RELATIVE_PATHS = (
    Path(EXTERNAL_RECORD_NAME),
    Path(FIELD_RECORD_NAME),
    Path(INSPECTION_NAME),
    IPA_RELATIVE_PATH,
)

_HEX40 = re.compile(r"^[0-9a-f]{40}$")
_GIT_OID = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
T = TypeVar("T")


class TrustedSignedCandidateError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise TrustedSignedCandidateError(message)


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
        # These are deliberately empty even though isolated Python ignores most caller PYTHON* state.
        "PYTHONPATH": "",
        "PYTHONSTARTUP": "",
    }


def _real_directory(path: Path, label: str) -> Path:
    try:
        metadata = path.lstat()
    except OSError as error:
        raise TrustedSignedCandidateError(f"{label} is unavailable: {path}") from error
    _require(not path.is_symlink() and stat.S_ISDIR(metadata.st_mode), f"{label} must be one real non-symlink directory")
    return path.absolute()


def _regular_bytes(path: Path, label: str) -> bytes:
    try:
        before = path.lstat()
    except OSError as error:
        raise TrustedSignedCandidateError(f"{label} is unavailable: {path}") from error
    _require(
        not path.is_symlink() and stat.S_ISREG(before.st_mode) and before.st_size > 0,
        f"{label} must be one non-empty regular non-symlink file",
    )
    try:
        raw = path.read_bytes()
        after = path.lstat()
    except OSError as error:
        raise TrustedSignedCandidateError(f"{label} is unreadable: {path}") from error
    identity_before = (
        before.st_dev,
        before.st_ino,
        before.st_mode,
        before.st_uid,
        before.st_gid,
        before.st_nlink,
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
        after.st_nlink,
        after.st_size,
        after.st_mtime_ns,
        after.st_ctime_ns,
    )
    _require(identity_before == identity_after and len(raw) == before.st_size, f"{label} changed while reading")
    return raw


def _git_bytes(repository: Path, *arguments: str, input_bytes: bytes | None = None) -> bytes:
    repository = _real_directory(repository, "frozen source repository")
    try:
        result = subprocess.run(
            ["/usr/bin/git", "-C", str(repository), *arguments],
            env=_closed_git_environment(),
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise TrustedSignedCandidateError("closed Git operation failed") from error
    if result.returncode != 0:
        raise TrustedSignedCandidateError("closed Git operation could not resolve frozen signing authority")
    return result.stdout


def _git_text(repository: Path, *arguments: str) -> str:
    try:
        return _git_bytes(repository, *arguments).decode("ascii").strip().lower()
    except UnicodeDecodeError as error:
        raise TrustedSignedCandidateError("Git object identity was not ASCII") from error


def _frozen_tool_bytes(
    frozen_source_repo: Path,
    *,
    source_commit: str,
    path: str,
    expected_blob: str,
) -> bytes:
    source = _git_text(frozen_source_repo, "rev-parse", "--verify", f"{source_commit}^{{commit}}")
    _require(source == source_commit, "frozen Capture source commit is unavailable or aliases another commit")
    actual_blob = _git_text(frozen_source_repo, "rev-parse", f"{source_commit}:{path}")
    _require(_GIT_OID.fullmatch(actual_blob) is not None, f"frozen tool Git object identity is malformed: {path}")
    _require(actual_blob == expected_blob, f"frozen tool Git blob is not accepted authority: {path}")
    raw = _git_bytes(frozen_source_repo, "cat-file", "blob", expected_blob)
    _require(raw, f"frozen tool Git blob is empty: {path}")
    rehashed = _git_bytes(frozen_source_repo, "hash-object", "--stdin", input_bytes=raw).decode("ascii").strip().lower()
    _require(rehashed == expected_blob, f"frozen tool bytes do not reproduce accepted Git blob: {path}")
    return raw


def _execute_frozen_apple_inspector(
    *,
    private_runner_bytes: bytes,
    inspector_bytes: bytes,
    retained_ipa: Path,
    expected_source_sha: str,
    intended_device_udid_file: Path,
    frozen_source_repo: Path,
    trusted_candidate_root: Path,
) -> None:
    _require(sys.platform == "darwin", "trusted signed-field reinspection requires macOS Apple signing tools")
    _require(_HEX40.fullmatch(expected_source_sha) is not None, "expected source SHA is not canonical lowercase 40-hex")
    frozen_source_repo = _real_directory(frozen_source_repo, "frozen source repository")
    _regular_bytes(retained_ipa, "retained IPA for Apple reinspection")

    inspection_output = trusted_candidate_root / "inspection"
    _require(not inspection_output.exists() and not inspection_output.is_symlink(), "trusted reinspection output already exists")

    # The inspector is passed only as an inherited descriptor.  The private runner source itself is
    # interpreter stdin, so neither authority-bearing Python subject is reopened from a mutable
    # candidate/repository pathname after its Git-object custody proof.
    with tempfile.TemporaryFile(prefix="nembra-final-go-inspector-") as inspector_subject:
        inspector_subject.write(inspector_bytes)
        inspector_subject.flush()
        inspector_subject.seek(0)
        inspector_fd = inspector_subject.fileno()
        command = [
            "/usr/bin/python3",
            "-I",
            "-",
            "--ipa",
            str(retained_ipa),
            "--expected-source-sha",
            expected_source_sha,
            "--intended-device-udid-file",
            str(intended_device_udid_file),
            "--repository-root",
            str(frozen_source_repo),
            "--canonical-inspector-fd",
            str(inspector_fd),
            "--output-dir",
            str(inspection_output),
        ]
        try:
            result = subprocess.run(
                command,
                cwd=Path("/"),
                env=_closed_python_environment(),
                input=private_runner_bytes,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                pass_fds=(inspector_fd,),
                check=False,
                timeout=180,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise TrustedSignedCandidateError("trusted Apple signed-field reinspection could not execute") from error
    if result.returncode != 0:
        # Do not replay stderr.  The frozen private runner intentionally treats the intended-device
        # value as verification-only input and redacts inspector diagnostics; a future diagnostic
        # regression must not turn Final GO into a privacy exfiltration surface.
        raise TrustedSignedCandidateError("frozen Apple signed-field inspector rejected the retained IPA")
    _require(not result.stdout.strip(), "frozen Apple signed-field inspector emitted unexpected stdout")
    _require(not result.stderr.strip(), "frozen Apple signed-field inspector emitted unexpected stderr")
    _real_directory(inspection_output, "trusted Apple reinspection output")


def _compare_retained_handoff(candidate_root: Path, trusted_candidate_root: Path) -> dict[str, dict[str, Any]]:
    candidate_inspection = _real_directory(candidate_root, "retained signed-field candidate root") / "inspection"
    trusted_inspection = _real_directory(trusted_candidate_root, "trusted reinspection candidate root") / "inspection"
    _real_directory(candidate_inspection, "retained signed-field inspection directory")
    _real_directory(trusted_inspection, "trusted Apple reinspection directory")

    evidence: dict[str, dict[str, Any]] = {}
    for relative in RETAINED_RELATIVE_PATHS:
        supplied = _regular_bytes(candidate_inspection / relative, f"retained candidate {relative}")
        trusted = _regular_bytes(trusted_inspection / relative, f"trusted reinspection {relative}")
        _require(
            supplied == trusted,
            f"retained candidate {relative} is not byte-identical to fresh frozen Apple reinspection",
        )
        evidence[str(relative)] = {
            "sha256": hashlib.sha256(trusted).hexdigest(),
            "byteCount": len(trusted),
        }
    return evidence


def verify_trusted_signed_candidate(
    *,
    candidate_root: Path,
    expected_source_sha: str,
    frozen_source_repo: Path,
    intended_device_udid_file: Path,
    semantic_builder: Callable[[Path], T],
) -> tuple[T, dict[str, Any]]:
    """Reinspect exact IPA with frozen Apple tooling, then semantic-validate only trusted outputs.

    `semantic_builder` receives a temporary candidate root whose `inspection/` directory was freshly
    emitted by the frozen canonical inspector.  It must consume everything it needs synchronously;
    the directory is deleted before this function returns.  This makes caller handoff JSON a
    comparison subject, never the source of signing/provisioning truth.
    """

    source = expected_source_sha.strip().lower()
    _require(_HEX40.fullmatch(source) is not None, "expected source SHA is not canonical lowercase 40-hex")
    _require(source == FROZEN_CAPTURE_SOURCE_COMMIT, "trusted Apple reinspection is pinned to the frozen #833 Capture source")
    candidate = _real_directory(candidate_root, "retained signed-field candidate root")
    frozen_repo = _real_directory(frozen_source_repo, "frozen source repository")
    retained_ipa = candidate / "inspection" / IPA_RELATIVE_PATH

    private_runner = _frozen_tool_bytes(
        frozen_repo,
        source_commit=source,
        path=PRIVATE_RUNNER_PATH,
        expected_blob=PRIVATE_RUNNER_BLOB,
    )
    inspector = _frozen_tool_bytes(
        frozen_repo,
        source_commit=source,
        path=INSPECTOR_PATH,
        expected_blob=INSPECTOR_BLOB,
    )

    with tempfile.TemporaryDirectory(prefix="nembra-final-go-apple-reinspection-") as temporary:
        trusted_root = Path(temporary) / "candidate"
        trusted_root.mkdir()
        _execute_frozen_apple_inspector(
            private_runner_bytes=private_runner,
            inspector_bytes=inspector,
            retained_ipa=retained_ipa,
            expected_source_sha=source,
            intended_device_udid_file=intended_device_udid_file,
            frozen_source_repo=frozen_repo,
            trusted_candidate_root=trusted_root,
        )
        handoff = _compare_retained_handoff(candidate, trusted_root)
        semantic = semantic_builder(trusted_root)

    return semantic, {
        "authority": TRUSTED_REINSPECTION_AUTHORITY,
        "candidateSourceCommitSHA": source,
        "privateRunnerPath": PRIVATE_RUNNER_PATH,
        "privateRunnerGitBlob": PRIVATE_RUNNER_BLOB,
        "canonicalInspectorPath": INSPECTOR_PATH,
        "canonicalInspectorGitBlob": INSPECTOR_BLOB,
        "appleVerificationPlatform": "macos-system-codesign-security",
        "intendedDeviceIdentifierHandling": "external-private-file-verification-only-not-recorded",
        "retainedHandoffByteIdentity": handoff,
        "physicalExperimentAuthorization": "not-granted",
    }
