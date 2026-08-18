#!/usr/bin/env python3
"""Bridge accepted V17 build-input review authority to the current field consumer.

This control successor preserves the accepted owner-reviewed generated/private
manifest authority, but closes the current contract drift:
- the field installer consumes NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256;
- the candidate's exact snapshot-helper Git bytes must derive the same manifest
  digest as the accepted V17 control helper before the inherited installer runs;
- the exact candidate bootstrap + installer Git bytes must prove that reviewed
  digest is required and transported into --accepted-generated-manifest-sha256.

This module creates no physical authority by itself.
"""
from __future__ import annotations

import contextlib
import hashlib
from pathlib import Path
import re
import subprocess
import types
from typing import Any, Iterator

PARENT_PATH = "scripts/ci/es80_authenticated_stationary_build_input_manifest_final_go.py"
PARENT_BLOB = "3379a31b2d8014365be257871b56c1ea75d048f3"
SNAPSHOT_HELPER_PATH = "scripts/ci/capture_accepted_build_input_snapshot.py"
BOOTSTRAP_PATH = "Scripts/bootstrap_capture_tuya_sdk.sh"
INSTALLER_PATH = "scripts/field/install_one_time_capture.command"
CURRENT_ENV_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_MANIFEST_SHA256"
LEGACY_ENV_KEY = "NEMBRA_CAPTURE_ACCEPTED_GENERATED_BUILD_INPUT_MANIFEST_SHA256"
INSTALLER_OPTION = "--accepted-generated-manifest-sha256"
MANIFEST_SCHEMA_VERSION = 1
EXPECTED_GENERATED_SUBJECTS = (
    "Podfile.lock",
    "NembraCapture.xcworkspace",
    "Pods",
    "LocalSecrets/TuyaSDK",
    "LocalSecrets/TuyaRuntime",
)
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


class CurrentManifestConsumerFinalGoError(RuntimeError):
    pass


def _closed_git_environment() -> dict[str, str]:
    return {
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp",
        "LANG": "C",
        "LC_ALL": "C",
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_NO_REPLACE_OBJECTS": "1",
        "GIT_OPTIONAL_LOCKS": "0",
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "core.fsmonitor",
        "GIT_CONFIG_VALUE_0": "false",
        "GIT_CONFIG_KEY_1": "core.hooksPath",
        "GIT_CONFIG_VALUE_1": "/dev/null",
    }


def _canonical_blob_oid(payload: bytes, accepted_oid: str) -> str:
    raw = b"blob " + str(len(payload)).encode("ascii") + b"\0" + payload
    if len(accepted_oid) == 40:
        return hashlib.sha1(raw).hexdigest()
    if len(accepted_oid) == 64:
        return hashlib.sha256(raw).hexdigest()
    raise CurrentManifestConsumerFinalGoError("unsupported Git object width")


def _git(root: Path, *arguments: str, binary: bool = False) -> bytes | str:
    root = root.expanduser().resolve(strict=True)
    try:
        completed = subprocess.run(
            ["/usr/bin/git", "-C", str(root), *arguments],
            env=_closed_git_environment(),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=not binary,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise CurrentManifestConsumerFinalGoError("exact Git authority unavailable") from error
    return bytes(completed.stdout) if binary else str(completed.stdout).strip()


def _exact_blob(
    root: Path,
    source: str,
    relative: str,
    *,
    expected_blob: str | None = None,
) -> tuple[str, bytes]:
    revision = source
    if source == "HEAD":
        revision = "HEAD"
    else:
        revision = source.lower()
        if HEX40.fullmatch(revision) is None:
            raise CurrentManifestConsumerFinalGoError("candidate source is malformed")
    resolved = str(_git(root, "rev-parse", f"{revision}:{relative}")).lower()
    if re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", resolved) is None:
        raise CurrentManifestConsumerFinalGoError(f"Git blob identity is malformed: {relative}")
    if expected_blob is not None and resolved != expected_blob:
        raise CurrentManifestConsumerFinalGoError(
            f"accepted Git blob moved for {relative}: expected {expected_blob}, got {resolved}"
        )
    payload = _git(root, "cat-file", "blob", resolved, binary=True)
    assert isinstance(payload, bytes)
    if not payload or _canonical_blob_oid(payload, resolved) != resolved:
        raise CurrentManifestConsumerFinalGoError(
            f"accepted Git bytes failed canonical identity: {relative}"
        )
    return resolved, payload


def _load_parent(root: Path):
    _blob, payload = _exact_blob(root, "HEAD", PARENT_PATH, expected_blob=PARENT_BLOB)
    module = types.ModuleType("nembra_v17_build_input_manifest_parent")
    module.__file__ = str((root / PARENT_PATH).resolve())
    try:
        exec(
            compile(payload, f"git:HEAD:{PARENT_PATH}", "exec", dont_inherit=True),
            module.__dict__,
        )
    except Exception as error:
        raise CurrentManifestConsumerFinalGoError(
            "accepted V17 build-input Final-GO parent could not execute"
        ) from error
    return module


def _load_candidate_snapshot_helper(candidate_repo: Path, source: str):
    blob, payload = _exact_blob(candidate_repo, source, SNAPSHOT_HELPER_PATH)
    module = types.ModuleType("nembra_current_candidate_snapshot_helper")
    module.__file__ = f"git:{source}:{SNAPSHOT_HELPER_PATH}"
    try:
        exec(compile(payload, module.__file__, "exec", dont_inherit=True), module.__dict__)
    except Exception as error:
        raise CurrentManifestConsumerFinalGoError(
            "current candidate snapshot helper could not execute"
        ) from error
    if getattr(module, "SCHEMA_VERSION", None) != MANIFEST_SCHEMA_VERSION:
        raise CurrentManifestConsumerFinalGoError("current candidate manifest schema moved")
    subjects = tuple(path.as_posix() for path in getattr(module, "GENERATED_SUBJECTS", ()))
    if subjects != EXPECTED_GENERATED_SUBJECTS:
        raise CurrentManifestConsumerFinalGoError("current candidate manifest subject set moved")
    derive = getattr(module, "generated_manifest_sha256", None)
    if not callable(derive):
        raise CurrentManifestConsumerFinalGoError(
            "current candidate snapshot helper exposes no digest authority"
        )
    return blob, module


def _derive_candidate_manifest(
    candidate_repo: Path,
    source: str,
) -> tuple[str, str]:
    blob, helper = _load_candidate_snapshot_helper(candidate_repo, source)
    try:
        first = helper.generated_manifest_sha256(candidate_repo, source)
        second = helper.generated_manifest_sha256(candidate_repo, source)
    except Exception as error:
        raise CurrentManifestConsumerFinalGoError(
            "current candidate helper rejected generated/private build inputs"
        ) from error
    if (
        not isinstance(first, str)
        or not isinstance(second, str)
        or HEX64.fullmatch(first) is None
        or first != first.lower()
        or first != second
    ):
        raise CurrentManifestConsumerFinalGoError(
            "current candidate generated/private manifest is unstable or malformed"
        )
    return blob, first


def _utf8_source(candidate_repo: Path, source: str, relative: str) -> str:
    _blob, payload = _exact_blob(candidate_repo, source, relative)
    try:
        return payload.decode("utf-8", "strict")
    except UnicodeDecodeError as error:
        raise CurrentManifestConsumerFinalGoError(
            f"candidate authority source is not UTF-8: {relative}"
        ) from error


def _validate_current_consumer(candidate_repo: Path, source: str) -> None:
    installer = _utf8_source(candidate_repo, source, INSTALLER_PATH)
    bootstrap = _utf8_source(candidate_repo, source, BOOTSTRAP_PATH)

    if CURRENT_ENV_KEY not in installer:
        raise CurrentManifestConsumerFinalGoError(
            "field installer does not require current reviewed manifest authority"
        )
    if INSTALLER_OPTION not in installer:
        raise CurrentManifestConsumerFinalGoError(
            "field installer does not transport reviewed manifest authority"
        )
    if f'"${{{CURRENT_ENV_KEY}}}"' not in installer:
        raise CurrentManifestConsumerFinalGoError(
            "field installer does not pass the reviewed manifest value to the orchestrator"
        )
    if SNAPSHOT_HELPER_PATH in installer or "generated_manifest_sha256(" in installer:
        raise CurrentManifestConsumerFinalGoError(
            "field installer may not self-derive the reviewed manifest authority"
        )
    if CURRENT_ENV_KEY not in bootstrap:
        raise CurrentManifestConsumerFinalGoError(
            "field bootstrap does not require current reviewed manifest authority"
        )
    if (
        SNAPSHOT_HELPER_PATH not in bootstrap
        or " manifest " not in bootstrap
        or "--source-sha" not in bootstrap
        or "shasum -a 256" not in bootstrap
        or "GENERATED_MANIFEST_SHA256" not in bootstrap
        or "ACCEPTED_GENERATED_MANIFEST_SHA256" not in bootstrap
    ):
        raise CurrentManifestConsumerFinalGoError(
            "field bootstrap does not rederive and compare the canonical accepted-input manifest"
        )
    if LEGACY_ENV_KEY in installer or LEGACY_ENV_KEY in bootstrap:
        raise CurrentManifestConsumerFinalGoError(
            "candidate still carries the retired build-input manifest environment key"
        )


@contextlib.contextmanager
def _current_contract(
    parent: Any,
    *,
    candidate_repo: Path,
    source: str,
) -> Iterator[dict[str, str | None]]:
    original_key = getattr(parent, "ENV_KEY", None)
    original_derive = getattr(parent, "derive_generated_manifest_sha256", None)
    if original_key != LEGACY_ENV_KEY or not callable(original_derive):
        raise CurrentManifestConsumerFinalGoError(
            "accepted V17 build-input control parent contract moved"
        )

    state: dict[str, str | None] = {"candidateHelperBlob": None, "digest": None}

    def derive_adapter(repo: Path, item_source: str) -> str:
        legacy = original_derive(repo, item_source)
        if not isinstance(legacy, str) or HEX64.fullmatch(legacy) is None:
            raise CurrentManifestConsumerFinalGoError(
                "accepted V17 control helper returned malformed manifest authority"
            )
        candidate_blob, current = _derive_candidate_manifest(repo, item_source)
        if legacy != current:
            raise CurrentManifestConsumerFinalGoError(
                "current candidate snapshot helper disagrees with accepted V17 manifest semantics"
            )
        previous_blob = state["candidateHelperBlob"]
        previous_digest = state["digest"]
        if previous_blob not in (None, candidate_blob) or previous_digest not in (None, current):
            raise CurrentManifestConsumerFinalGoError(
                "candidate manifest authority changed during Final-GO"
            )
        state["candidateHelperBlob"] = candidate_blob
        state["digest"] = current
        return current

    parent.ENV_KEY = CURRENT_ENV_KEY
    parent.derive_generated_manifest_sha256 = derive_adapter
    try:
        yield state
    finally:
        parent.ENV_KEY = original_key
        parent.derive_generated_manifest_sha256 = original_derive


def build(
    *,
    candidate_repo: Path,
    source: str,
    parent_module: Any | None = None,
    **kwargs: Any,
) -> dict[str, Any]:
    candidate_repo = candidate_repo.expanduser().resolve(strict=True)
    source = source.lower()
    if HEX40.fullmatch(source) is None:
        raise CurrentManifestConsumerFinalGoError("Final-GO candidate source is malformed")
    if str(_git(candidate_repo, "rev-parse", "HEAD")).lower() != source:
        raise CurrentManifestConsumerFinalGoError("candidate checkout is not exact reviewed source")
    if str(_git(candidate_repo, "status", "--porcelain=v1", "--untracked-files=no")):
        raise CurrentManifestConsumerFinalGoError("candidate tracked worktree is not clean")

    _validate_current_consumer(candidate_repo, source)

    root = Path(__file__).resolve().parents[2]
    parent = parent_module or _load_parent(root)
    parent_build = getattr(parent, "build", None)
    if not callable(parent_build):
        raise CurrentManifestConsumerFinalGoError("accepted V17 parent exposes no build")

    with _current_contract(parent, candidate_repo=candidate_repo, source=source) as state:
        record = parent_build(candidate_repo=candidate_repo, source=source, **kwargs)

    if not isinstance(record, dict):
        raise CurrentManifestConsumerFinalGoError("accepted V17 parent returned no Final-GO record")
    digest = state.get("digest")
    helper_blob = state.get("candidateHelperBlob")
    if not isinstance(digest, str) or not isinstance(helper_blob, str):
        raise CurrentManifestConsumerFinalGoError(
            "accepted build completed without current manifest compatibility proof"
        )
    if record.get("acceptedGeneratedBuildInputManifestSHA256") != digest:
        raise CurrentManifestConsumerFinalGoError(
            "accepted V17 parent did not retain reviewed manifest authority"
        )
    authority = record.get("generatedBuildInputManifestAuthority")
    if not isinstance(authority, dict) or authority.get("installerEnvironmentKey") != CURRENT_ENV_KEY:
        raise CurrentManifestConsumerFinalGoError(
            "accepted V17 parent did not use the current closed installer environment key"
        )
    if record.get("physicalResultCollected") is not False:
        raise CurrentManifestConsumerFinalGoError(
            "current consumer control child may not promote physical authority"
        )

    return {
        **record,
        "generatedBuildInputManifestAuthority": {
            **authority,
            "currentCandidateSnapshotHelperGitBlob": helper_blob,
            "installerEnvironmentKey": CURRENT_ENV_KEY,
            "installerConsumerIntegrated": True,
            "consumerContract": "nembra-capture-current-generated-manifest-consumer-v1",
            "physicalAuthorityCreated": False,
        },
    }


if __name__ == "__main__":
    raise SystemExit(
        "Current manifest-consumer Final-GO control is an exact-head issuer ingredient; "
        "final composed candidate + private install acceptance remain NO-GO."
    )
