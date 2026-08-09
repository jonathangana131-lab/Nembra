#!/usr/bin/env python3
# Source contract for trusted Capture Xcode build-graph custody.
# The trusted authority runner must reject changes to the exact host-execution-bearing
# Xcode/SwiftPM graph reviewed for the first ES80 field build before compilation.

from __future__ import annotations

import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"

EXPECTED_BUILD_GRAPH = {
    "Nembra.xcodeproj/project.pbxproj": "d87024ba057add61a7d45ce8b69ac9947e6d2117",
    "Nembra.xcodeproj/xcshareddata/xcschemes/Nembra.xcscheme": "64ef64f110265194d904ea0cbf177bbf264871c9",
    "Packages/NembraCore/Package.swift": "26544e273397020fae34c7034992071a9861c131",
    "Packages/NembraBluetoothCapture/Package.swift": "3bcda7fa8a350ade75bd8b7b228c3c95ca319bda",
}


class TrustedXcodeBuildGraphCustodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def _custody_block(self) -> str:
        authority = self.workflow.index("  capture-simulator-qa:\n")
        authority_block = self.workflow[authority:]
        custody = authority_block.index("- name: Verify trusted build graph custody")
        build = authority_block.index("- name: Build, test, and capture Simulator states")
        self.assertLess(custody, build)
        return authority_block[custody:build]

    def test_authority_verifies_build_graph_immediately_before_candidate_build(self) -> None:
        between = self._custody_block()
        self.assertIn("/usr/bin/python3 -I - <<'PY'", between)
        self.assertIn('sha1(', between)
        self.assertIn('b"blob "', between)

    def test_build_graph_reads_are_descriptor_bound_and_no_follow_every_component(self) -> None:
        between = self._custody_block()
        self.assertIn('hasattr(os, "O_NOFOLLOW")', between)
        self.assertIn("os.O_DIRECTORY", between)
        self.assertIn("os.O_NOFOLLOW", between)
        self.assertIn("dir_fd=current_fd", between)
        self.assertIn("os.fstat(subject_fd)", between)
        self.assertIn("os.read(subject_fd", between)
        self.assertIn("identity_before", between)
        self.assertIn("identity_after", between)
        self.assertNotIn("path.is_file()", between)
        self.assertNotIn("path.is_symlink()", between)
        self.assertNotIn("path.read_bytes()", between)

    def test_leaf_only_symlink_check_witness_does_not_cover_symlinked_ancestor(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workspace = root / "workspace"
            workspace.mkdir()
            real_project = root / "real-project"
            real_project.mkdir()
            (real_project / "project.pbxproj").write_text("// reviewed-looking bytes\n", encoding="utf-8")
            (workspace / "Nembra.xcodeproj").symlink_to(real_project, target_is_directory=True)

            leaf = workspace / "Nembra.xcodeproj" / "project.pbxproj"
            self.assertTrue(leaf.is_file())
            self.assertFalse(leaf.is_symlink())
            self.assertTrue(leaf.parent.is_symlink())

    def test_descriptor_no_follow_witness_rejects_symlinked_build_graph_ancestors(self) -> None:
        if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
            self.skipTest("platform does not expose O_DIRECTORY/O_NOFOLLOW")

        for ancestor in ("Nembra.xcodeproj", "Packages"):
            with self.subTest(ancestor=ancestor), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                workspace = root / "workspace"
                workspace.mkdir()
                external = root / "external"
                external.mkdir()
                (workspace / ancestor).symlink_to(external, target_is_directory=True)

                directory_flags = (
                    os.O_RDONLY
                    | os.O_DIRECTORY
                    | os.O_NOFOLLOW
                    | getattr(os, "O_CLOEXEC", 0)
                )
                root_fd = os.open(workspace, directory_flags)
                try:
                    with self.assertRaises(OSError):
                        os.open(ancestor, directory_flags, dir_fd=root_fd)
                finally:
                    os.close(root_fd)

    def test_exact_reviewed_build_graph_subjects_are_fail_closed(self) -> None:
        for path, blob in EXPECTED_BUILD_GRAPH.items():
            with self.subTest(path=path):
                self.assertIn(f'"{path}": "{blob}"', self.workflow)

    def test_candidate_prevalidation_does_not_share_authority_runner(self) -> None:
        prevalidation = self.workflow.index("  prevalidate-candidate:\n")
        authority = self.workflow.index("  capture-simulator-qa:\n")
        self.assertLess(prevalidation, authority)
        authority_block = self.workflow[authority:]
        self.assertIn("needs: [resolve, prevalidate-candidate]", authority_block)


if __name__ == "__main__":
    unittest.main()
