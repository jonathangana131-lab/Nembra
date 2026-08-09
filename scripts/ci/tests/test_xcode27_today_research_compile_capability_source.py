#!/usr/bin/env python3
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRAPPER = ROOT / "scripts/ci/xcode27_today_research_field_candidate.sh"
PRODUCER = ROOT / "scripts/ci/xcode27_signed_field_candidate.sh"


class TodayResearchCompileCapabilitySourceTests(unittest.TestCase):
    def setUp(self):
        self.wrapper = WRAPPER.read_text(encoding="utf-8")
        self.producer = PRODUCER.read_text(encoding="utf-8")
        self.combined = self.wrapper + "\n" + self.producer

    def test_today_flag_is_not_treated_as_proven_by_environment_injection_alone(self):
        self.assertIn("NEMBRA_ES80_TODAY_RESEARCH", self.wrapper)
        self.assertIn("OTHER_SWIFT_FLAGS", self.wrapper)

        # The signed field path must mechanically bind the dedicated compile condition to the
        # actual NembraBluetoothCapture target produced by the Release archive. Merely exporting
        # OTHER_SWIFT_FLAGS before delegating is not evidence that the Swift package target saw it.
        self.assertIn("NembraBluetoothCapture", self.combined)
        self.assertIn("today_research_compile_capability=verified", self.combined)

    def test_candidate_cannot_report_success_before_compile_capability_proof(self):
        proof = self.combined.find("today_research_compile_capability=verified")
        success = self.combined.find("Signed Nembra iOS field-build CANDIDATE retained at:")
        self.assertNotEqual(proof, -1)
        self.assertNotEqual(success, -1)
        self.assertLess(proof, success)

    def test_compile_proof_is_bound_to_retained_archive_evidence(self):
        # A valid implementation may perform the check in the TODAY wrapper or canonical producer,
        # but the proof has to consume retained archive/build evidence and name the actual package
        # target plus compile condition. This intentionally avoids prescribing one shell structure.
        self.assertIn("xcodebuild-archive.log", self.combined)
        self.assertIn("NembraBluetoothCapture", self.combined)
        self.assertIn("NEMBRA_ES80_TODAY_RESEARCH", self.combined)

    def test_ordinary_signed_producer_remains_non_authorizing(self):
        # The canonical producer must not unconditionally turn every Release archive into a TODAY
        # research build. The dedicated capability remains opt-in through the TODAY entry point.
        self.assertNotIn(
            '"OTHER_SWIFT_FLAGS=$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH" \\\n  archive',
            self.producer,
        )


if __name__ == "__main__":
    unittest.main()
