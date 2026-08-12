#!/usr/bin/env python3
"""Source-contract regressions for the trusted V16 standalone Capture gate."""

from pathlib import Path
import unittest

REPOSITORY = Path(__file__).resolve().parents[3]
WORKFLOW = REPOSITORY / ".github/workflows/capture-v16-trusted-standalone-command.yml"


class CaptureV16TrustedStandaloneCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = WORKFLOW.read_text(encoding="utf-8")

    def test_owner_command_and_same_repo_admission_are_trusted(self) -> None:
        source = self.source
        self.assertIn("issue_comment:", source)
        self.assertIn("github.event.comment.body == '/capture-xcode27'", source)
        for association in ("OWNER", "MEMBER", "COLLABORATOR"):
            self.assertIn(f"github.event.comment.author_association == '{association}'", source)
        self.assertIn("github.rest.pulls.get", source)
        self.assertIn("pr.state !== 'open'", source)
        self.assertIn("pr.head.repo?.full_name === repository", source)
        self.assertIn("core.setOutput('head_sha', pr.head.sha)", source)

    def test_live_head_is_revalidated_before_and_after_candidate_qa(self) -> None:
        source = self.source
        preflight = source.index("- name: Revalidate live PR before executing candidate bytes")
        checkout = source.index("- name: Checkout immutable PR head")
        verify = source.index("- name: Verify immutable PR head")
        product = source.index("- name: Verify software-only standalone product")
        postflight = source.index("- name: Revalidate exact PR head after standalone QA")
        upload = source.index("- name: Upload trusted standalone evidence")

        self.assertLess(preflight, checkout)
        self.assertLess(checkout, verify)
        self.assertLess(verify, product)
        self.assertLess(product, postflight)
        self.assertLess(postflight, upload)
        self.assertIn("pr.head.sha !== process.env.EXPECTED_HEAD_SHA", source[preflight:checkout])
        self.assertIn("pr.head.sha !== process.env.EXPECTED_HEAD_SHA", source[postflight:upload])
        self.assertIn("moved during QA", source[postflight:upload])
        self.assertIn("ref: ${{ needs.resolve.outputs.head_sha }}", source[checkout:verify])
        self.assertIn('test "$actual" = "$EXPECTED_HEAD_SHA"', source[verify:])
        self.assertIn(
            "capture-v16-trusted-standalone-${{ needs.resolve.outputs.pr_number }}-${{ needs.resolve.outputs.head_sha }}",
            source,
        )

    def test_trusted_gate_builds_standalone_product_and_preserves_truth_boundary(self) -> None:
        source = self.source
        self.assertIn("swift build", source)
        for test_name in (
            "CoreBluetoothCaptureMappingTests",
            "TuyaAuthenticatedReadOnlyPreflightTests",
            "TuyaAuthenticatedReadOnlyCommandFenceSourceTests",
            "CaptureFirstFoldCopySourceTests",
        ):
            self.assertIn(f"swift test --filter {test_name}", source)
        self.assertIn("-project NembraCapture.xcodeproj", source)
        self.assertIn("-scheme 'Nembra Capture'", source)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", source)
        self.assertIn("test ! -e scripts/field/install_one_time_capture.command", source)
        for key in (
            "NembraCaptureBuildIdentifier",
            "NembraCaptureSourceCommitSHA",
            "NembraCaptureTuyaDependencyLockSHA256",
            "NembraCaptureProcedureIdentifier",
        ):
            self.assertIn(key, source)
        self.assertIn("Trusted public/unprovisioned build carried forbidden field authority", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
