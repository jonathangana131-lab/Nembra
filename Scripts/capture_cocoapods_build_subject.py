#!/usr/bin/env python3
"""Bind the generated CocoaPods field-build graph to an exact reviewed digest.

This helper fingerprints only build-subject metadata/bytes: Podfile.lock, Pods/, and
NembraCapture.xcworkspace/. It never serializes private Tuya credentials, device
identifiers, or secret values. The digest is suitable for external review/custody.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
import tempfile
from pathlib import Path
from typing import Iterable


class GeneratedSubjectError(RuntimeError):
    pass


def _load_provenance_module():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location("capture_tuya_private_input_provenance", helper)
    if spec is None or spec.loader is None:
        raise GeneratedSubjectError("Capture provenance helper could not be loaded")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


provenance = _load_provenance_module()


def _generation_snapshot(
    *,
    lockfile: Path,
    pods: Path,
    workspace: Path,
) -> tuple[object, ...]:
    lock_identity = provenance._regular_file_generation_identity(lockfile)
    pods_snapshot = provenance._tree_generation_snapshot(pods)
    workspace_snapshot = provenance._tree_generation_snapshot(workspace)

    provenance._assert_tree_generation_snapshot_unchanged(pods, pods_snapshot)
    provenance._assert_tree_generation_snapshot_unchanged(workspace, workspace_snapshot)
    if provenance._regular_file_generation_identity(lockfile) != lock_identity:
        raise GeneratedSubjectError("Podfile.lock changed while the CocoaPods build subject was snapshotted")
    return (lock_identity, pods_snapshot, workspace_snapshot)


def _feed(digest: "hashlib._Hash", value: bytes) -> None:
    digest.update(len(value).to_bytes(8, "big"))
    digest.update(value)


def subject_digest(
    *,
    lockfile: Path,
    pods: Path,
    workspace: Path,
) -> str:
    before = _generation_snapshot(lockfile=lockfile, pods=pods, workspace=workspace)
    lock_sha256 = provenance._read_stable_regular_file_sha256(lockfile)[1]
    pods_sha256 = provenance._tree_fingerprint(pods)
    workspace_sha256 = provenance._tree_fingerprint(workspace)
    after = _generation_snapshot(lockfile=lockfile, pods=pods, workspace=workspace)
    if after != before:
        raise GeneratedSubjectError("CocoaPods generated build subject changed while it was fingerprinted")

    digest = hashlib.sha256()
    _feed(digest, b"nembra-cocoapods-generated-build-subject-v1")
    _feed(digest, bytes.fromhex(lock_sha256))
    _feed(digest, bytes.fromhex(pods_sha256))
    _feed(digest, bytes.fromhex(workspace_sha256))
    return digest.hexdigest()


def _canonical_expected(value: str) -> str:
    normalized = value.lower()
    if len(normalized) != 64 or any(character not in "0123456789abcdef" for character in normalized):
        raise GeneratedSubjectError("accepted CocoaPods build-subject digest must be exactly 64 hex characters")
    return normalized


def _self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-subject-selftest-") as temporary:
        root = Path(temporary)
        lockfile = root / "Podfile.lock"
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        (pods / "Target Support Files/Pods-NembraCapture").mkdir(parents=True)
        workspace.mkdir()
        lockfile.write_text("PODS:\n  - Example (1.0)\n", encoding="utf-8")
        generated = pods / "Target Support Files/Pods-NembraCapture/Pods-NembraCapture.debug.xcconfig"
        generated.write_text("SETTING = REVIEWED\n", encoding="utf-8")
        (workspace / "contents.xcworkspacedata").write_text("REVIEWED\n", encoding="utf-8")

        first = subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if _canonical_expected(first.upper()) != first:
            raise GeneratedSubjectError("digest canonicalization self-test failed")
        if subject_digest(lockfile=lockfile, pods=pods, workspace=workspace) != first:
            raise GeneratedSubjectError("stable generated build subject produced an unstable digest")

        generated.write_text("SETTING = SUBSTITUTED\n", encoding="utf-8")
        second = subject_digest(lockfile=lockfile, pods=pods, workspace=workspace)
        if second == first:
            raise GeneratedSubjectError("generated build mutation did not change the subject digest")
    print("CocoaPods generated build-subject self-test passed.")
    return 0


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Nembra Capture CocoaPods generated build-subject custody")
    parser.add_argument("mode", choices=("digest", "verify"), nargs="?", default="digest")
    parser.add_argument("--lockfile")
    parser.add_argument("--pods")
    parser.add_argument("--workspace")
    parser.add_argument("--expected")
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    if arguments.self_test:
        try:
            return _self_test()
        except (OSError, GeneratedSubjectError, provenance.ProvenanceError) as error:
            print(f"ERROR: {error}", file=os.sys.stderr)
            return 2

    if not arguments.lockfile or not arguments.pods or not arguments.workspace:
        print("ERROR: --lockfile, --pods, and --workspace are required", file=os.sys.stderr)
        return 2

    try:
        digest = subject_digest(
            lockfile=Path(arguments.lockfile),
            pods=Path(arguments.pods),
            workspace=Path(arguments.workspace),
        )
        if arguments.mode == "verify":
            if arguments.expected is None:
                raise GeneratedSubjectError("--expected is required in verify mode")
            expected = _canonical_expected(arguments.expected)
            if digest != expected:
                raise GeneratedSubjectError(
                    "generated CocoaPods build subject does not match the externally accepted digest"
                )
            print("Accepted CocoaPods generated build subject matched.")
        else:
            print(digest)
    except (OSError, GeneratedSubjectError, provenance.ProvenanceError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
