#!/usr/bin/env python3
"""Compute a race-checked digest for CocoaPods-generated Capture build inputs.

This is evidence about generated build bytes, not physical or protocol authority.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import os
from pathlib import Path

SCHEMA = b"nembra-capture-cocoapods-generated-subject-v1"


class SubjectError(RuntimeError):
    pass


def _load_provenance_helper():
    helper = Path(__file__).with_name("capture_tuya_private_input_provenance.py")
    spec = importlib.util.spec_from_file_location("nembra_tuya_private_input_provenance", helper)
    if spec is None or spec.loader is None:
        raise SubjectError("private-input provenance helper unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _component(label: bytes, digest_hex: str) -> bytes:
    if len(digest_hex) != 64 or any(c not in "0123456789abcdef" for c in digest_hex):
        raise SubjectError("component digest is not canonical SHA-256")
    raw = bytes.fromhex(digest_hex)
    return len(label).to_bytes(4, "big") + label + len(raw).to_bytes(4, "big") + raw


def build_subject(pods: Path, workspace: Path) -> str:
    provenance = _load_provenance_helper()
    try:
        pods_before = provenance._tree_generation_snapshot(pods)
        workspace_before = provenance._tree_generation_snapshot(workspace)
        pods_digest = provenance._tree_fingerprint(pods)
        workspace_digest = provenance._tree_fingerprint(workspace)
        provenance._assert_tree_generation_snapshot_unchanged(pods, pods_before)
        provenance._assert_tree_generation_snapshot_unchanged(workspace, workspace_before)
    except (OSError, provenance.ProvenanceError) as error:
        raise SubjectError(str(error)) from error

    hasher = hashlib.sha256()
    hasher.update(len(SCHEMA).to_bytes(4, "big"))
    hasher.update(SCHEMA)
    hasher.update(_component(b"Pods", pods_digest))
    hasher.update(_component(b"NembraCapture.xcworkspace", workspace_digest))
    return hasher.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pods", type=Path, required=True)
    parser.add_argument("--workspace", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        digest = build_subject(arguments.pods, arguments.workspace)
    except (OSError, SubjectError) as error:
        print(f"ERROR: {error}", file=os.sys.stderr)
        return 2
    print(digest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
