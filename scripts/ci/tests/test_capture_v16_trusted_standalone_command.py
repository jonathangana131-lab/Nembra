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

    def test_deployed_owner_only_default_branch_admission_is_preserved(self) -> None:
        source = self.source
        self.assertIn("issue_comment:", source)
        self.assertIn("github.event.comment.body == '/capture-v16-xcode27'", source)
        self.assertIn("github.actor == github.repository_owner", source)
        self.assertIn("const baseMain = pr.base.ref === context.payload.repository.default_branch", source)
        self.assertIn("if (!baseMain)", source)
        self.assertIn("core.setOutput('head_sha', pr.head.sha)", source)
        self.assertIn("core.setOutput('base_main', String(baseMain))", source)
        self.assertIn("actions/github-script@3a2844b7e9c422d3c10d287c895573f7108da1b3", source)

    def test_candidate_checkout_drops_persisted_credentials(self) -> None:
        source = self.source
        checkout = source.index("- name: Checkout immutable exact Capture head")
        verify = source.index("- name: Verify immutable checkout and toolchain")
        checkout_block = source[checkout:verify]
        self.assertIn("actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803", checkout_block)
        self.assertIn("ref: ${{ needs.resolve.outputs.head_sha }}", checkout_block)
        self.assertIn("fetch-depth: 1", checkout_block)
        self.assertIn("persist-credentials: false", checkout_block)
        self.assertIn('test "$actual" = "$EXPECTED_HEAD_SHA"', source[verify:])

    def test_existing_truth_and_read_only_gates_are_not_weakened(self) -> None:
        source = self.source
        for test_name in (
            "PassiveBluetoothCaptureTests",
            "PassiveBluetoothCaptureObservationBoundaryTests",
            "PassiveBluetoothObservationWindowDurationAssessmentTests",
            "CoreBluetoothCaptureMappingTests",
            "TuyaAuthenticatedReadOnlyPreflightTests",
            "TuyaAuthenticatedReadOnlyCommandFenceSourceTests",
            "CaptureFirstFoldCopySourceTests",
        ):
            self.assertIn(f"swift test --filter {test_name}", source)
        self.assertIn("\\.writeValue(", source)
        self.assertIn("Standalone Capture source contains an application characteristic write path.", source)
        self.assertIn("test ! -e scripts/field/install_one_time_capture.command", source)
        self.assertIn("-project NembraCapture.xcodeproj", source)
        self.assertIn("-scheme 'Nembra Capture'", source)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", source)
        for key in (
            "NembraCaptureBuildIdentifier",
            "NembraCaptureSourceCommitSHA",
            "NembraCaptureTuyaDependencyLockSHA256",
            "NembraCaptureProcedureIdentifier",
        ):
            self.assertIn(key, source)
        self.assertIn("Public standalone build carried forbidden field authority", source)

    def test_post_qa_freshness_is_independently_rechecked_on_hosted_runner(self) -> None:
        source = self.source
        self_hosted_postflight = source.index("- name: Reject head movement after trusted acceptance")
        hosted_job = source.index("  accept-current-head:")
        hosted_postflight = source.index("- name: Revalidate exact PR head after trusted standalone QA")
        self.assertLess(self_hosted_postflight, hosted_job)
        self.assertLess(hosted_job, hosted_postflight)
        hosted_header = source[hosted_job:hosted_postflight]
        self.assertIn("needs: [resolve, standalone]", hosted_header)
        self.assertIn("needs.standalone.result == 'success'", hosted_header)
        self.assertIn("runs-on: ubuntu-latest", hosted_header)
        hosted_check = source[hosted_postflight:]
        self.assertIn("pr.state !== 'open'", hosted_check)
        self.assertIn("pr.head.repo.full_name !== repository", hosted_check)
        self.assertIn("pr.base.ref !== context.payload.repository.default_branch", hosted_check)
        self.assertIn("pr.head.sha !== process.env.EXPECTED_HEAD_SHA", hosted_check)
        self.assertIn("hosted acceptance is non-evidence", hosted_check)


if __name__ == "__main__":
    unittest.main(verbosity=2)
