#!/usr/bin/env python3
"""Adversarial custody tests for generated CocoaPods build-subject symlinks.

A generated tree digest cannot treat symlink text alone as closed build authority:
Xcode can consume bytes behind that stable pathname after the digest is reviewed.
The helper may either reject out-of-subject symlinks outright or bind their
resolved target bytes through an explicitly admitted root, but it must never
silently return the same authority after those consumed bytes change.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
HELPER_PATH = REPOSITORY / "Scripts" / "capture_cocoapods_build_subject.py"

spec = importlib.util.spec_from_file_location("capture_cocoapods_build_subject", HELPER_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("could not load CocoaPods build-subject helper")
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class CocoaPodsSymlinkTargetCustodyTests(unittest.TestCase):
    def _roots(self, root: Path) -> tuple[Path, Path]:
        pods = root / "Pods"
        workspace = root / "NembraCapture.xcworkspace"
        pods.mkdir()
        workspace.mkdir()
        (workspace / "contents.xcworkspacedata").write_text("workspace\n", encoding="utf-8")
        return pods, workspace

    def test_external_symlink_target_bytes_cannot_change_under_same_subject(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-symlink-") as temporary:
            root = Path(temporary)
            pods, workspace = self._roots(root)
            external = root / "outside"
            external.mkdir()
            target = external / "GeneratedConfig.xcconfig"
            target.write_text("SETTING = REVIEWED\n", encoding="utf-8")
            (pods / "GeneratedConfig.xcconfig").symlink_to(target)

            try:
                reviewed = helper.build_subject_digest(pods, workspace)
            except helper.BuildSubjectError:
                return  # Rejecting an unadmitted external target is fail-closed.

            target.write_text("SETTING = SUBSTITUTED\n", encoding="utf-8")
            try:
                substituted = helper.build_subject_digest(pods, workspace)
            except helper.BuildSubjectError:
                return  # Detecting the changed target is also fail-closed.

            self.assertNotEqual(
                substituted,
                reviewed,
                "generated build-subject authority stayed identical while bytes behind a stable external symlink changed",
            )

    def test_broken_generated_symlink_is_not_authoritative(self) -> None:
        with tempfile.TemporaryDirectory(prefix="nembra-cocoapods-broken-symlink-") as temporary:
            root = Path(temporary)
            pods, workspace = self._roots(root)
            (pods / "LateBoundConfig.xcconfig").symlink_to(root / "not-created-yet.xcconfig")

            with self.assertRaises(
                helper.BuildSubjectError,
                msg="a broken generated symlink can acquire build-affecting bytes after review and must fail closed",
            ):
                helper.build_subject_digest(pods, workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)
