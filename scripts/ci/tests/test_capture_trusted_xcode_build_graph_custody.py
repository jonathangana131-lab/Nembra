#!/usr/bin/env python3
# Source contract for trusted Capture Xcode build-graph custody.
# The trusted authority runner must reject changes to the exact host-execution-bearing
# Xcode/SwiftPM graph reviewed for the first ES80 field build before compilation.

from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github" / "workflows" / "capture-xcode27-trusted-command.yml"

EXPECTED_BUILD_GRAPH = {
    "Nembra.xcodeproj/project.pbxproj": "d87024ba057add61a7d45ce8b69ac9947e6d2117",
    "Nembra.xcodeproj/xcshareddata/xcschemes/Nembra.xcscheme": "64ef64f110265194d904ea0cbf177bbf264871c9",
    "Packages/NembraCore/Package.swift": "26544e273397020fae34c7034992071a9861c131",
    "Packages/NembraBluetoothCapture/Package.swift": "3bcda7fa8a350ade75bd8b7b228c3c95ca319bda",
}
CANONICAL_SCHEME = "Nembra.xcodeproj/xcshareddata/xcschemes/Nembra.xcscheme"


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
        self.assertIn("/usr/bin/python3 - <<'PY'", between)
        self.assertIn('sha1(b"blob "', between)
        self.assertIn("path.is_symlink()", between)

    def test_exact_reviewed_build_graph_subjects_are_fail_closed(self) -> None:
        for path, blob in EXPECTED_BUILD_GRAPH.items():
            with self.subTest(path=path):
                self.assertIn(f'"{path}": "{blob}"', self.workflow)

    def test_candidate_cannot_add_alternate_xcode_scheme_selection_surface(self) -> None:
        """The authority build must have exactly one selectable scheme for this project.

        Pinning the shared scheme bytes is insufficient if a candidate can add a same-name private
        scheme under xcuserdata (or another tracked .xcscheme) that xcodebuild may select. The
        trusted fence must enumerate the candidate tree immediately before xcodebuild and fail
        closed unless the canonical reviewed shared scheme is the only .xcscheme present.
        """
        between = self._custody_block()
        self.assertIn(f'canonical_scheme = "{CANONICAL_SCHEME}"', between)
        self.assertIn('root.rglob("*.xcscheme")', between)
        self.assertIn("scheme_paths", between)
        self.assertIn("canonical_scheme", between)
        self.assertRegex(
            between,
            r"if\s+scheme_paths\s*!=\s*\{canonical_scheme\}\s*:",
            "trusted build-graph custody must reject every extra candidate .xcscheme path",
        )

    def test_candidate_prevalidation_does_not_share_authority_runner(self) -> None:
        prevalidation = self.workflow.index("  prevalidate-candidate:\n")
        authority = self.workflow.index("  capture-simulator-qa:\n")
        self.assertLess(prevalidation, authority)
        authority_block = self.workflow[authority:]
        self.assertIn("needs: [resolve, prevalidate-candidate]", authority_block)


if __name__ == "__main__":
    unittest.main()
