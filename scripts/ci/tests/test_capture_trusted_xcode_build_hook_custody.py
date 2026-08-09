#!/usr/bin/env python3
"""Source contract for host-executable build-hook custody in trusted Capture Xcode authority."""
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"


class TrustedXcodeBuildHookCustodyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.workflow = WORKFLOW.read_text(encoding="utf-8")

    def test_trusted_build_hook_fence_runs_before_xcode_authority(self) -> None:
        workflow = self.workflow
        authority_job = workflow.index("  capture-simulator-qa:\n")
        fence = workflow.index("- name: Reject host-executable candidate build hooks", authority_job)
        build = workflow.index("- name: Build, test, and capture Simulator states", authority_job)
        self.assertLess(fence, build)

    def test_fence_rejects_known_host_execution_surfaces(self) -> None:
        workflow = self.workflow
        required_markers = (
            "PBXShellScriptBuildPhase",
            "PBXBuildRule",
            "PBXLegacyTarget",
            "XCRemoteSwiftPackageReference",
            "XCLocalSwiftPackageReference",
            "XCSwiftPackageProductDependency",
            "baseConfigurationReference",
            "SWIFT_EXEC",
            "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC",
            "OTHER_SWIFT_FLAGS",
            "OTHER_CFLAGS",
            "OTHER_CPLUSPLUSFLAGS",
            "OTHER_LDFLAGS",
        )
        for marker in required_markers:
            with self.subTest(marker=marker):
                self.assertIn(marker, workflow)

    def test_fence_is_default_branch_inline_authority_not_candidate_script(self) -> None:
        workflow = self.workflow
        authority_job = workflow.index("  capture-simulator-qa:\n")
        fence = workflow.index("- name: Reject host-executable candidate build hooks", authority_job)
        build = workflow.index("- name: Build, test, and capture Simulator states", authority_job)
        block = workflow[fence:build]
        self.assertIn("/usr/bin/python3 -I - <<'PY'", block)
        self.assertIn('Path("Nembra.xcodeproj/project.pbxproj")', block)
        self.assertNotIn("scripts/ci/", block)


if __name__ == "__main__":
    unittest.main()
