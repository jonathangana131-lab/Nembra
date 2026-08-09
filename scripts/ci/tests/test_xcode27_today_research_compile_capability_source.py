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

    def test_today_flag_is_not_treated_as_proven_by_environment_injection_alone(self):
        self.assertIn("NEMBRA_ES80_TODAY_RESEARCH", self.wrapper)
        self.assertIn("OTHER_SWIFT_FLAGS", self.wrapper)
        self.assertIn('ARCHIVE_LOG="$QUARANTINED_CANDIDATE/logs/xcodebuild-archive.log"', self.wrapper)
        self.assertIn('module = "NembraBluetoothCapture"', self.wrapper)
        self.assertIn('condition = "NEMBRA_ES80_TODAY_RESEARCH"', self.wrapper)
        self.assertIn("condition_pattern.search(line)", self.wrapper)
        self.assertIn("today_research_compile_capability=verified", self.wrapper)

    def test_candidate_cannot_report_success_before_compile_capability_proof(self):
        producer_call = self.wrapper.index('"$CANONICAL_PRODUCER" "$@"')
        archive_proof = self.wrapper.index('condition_pattern.search(line)')
        receipt = self.wrapper.index('echo "today_research_compile_capability=verified"')
        publication = self.wrapper.index('rename_exclusive(source, destination')
        final_reopen = self.wrapper.index("grep -c '^today_research_compile_capability=verified$'")
        success = self.wrapper.index('Signed TODAY research Nembra iOS field-build CANDIDATE retained at:')

        self.assertLess(producer_call, archive_proof)
        self.assertLess(archive_proof, receipt)
        self.assertLess(receipt, publication)
        self.assertLess(publication, final_reopen)
        self.assertLess(final_reopen, success)

    def test_final_path_stays_absent_until_proven_candidate_is_atomically_published(self):
        self.assertIn('QUARANTINED_CANDIDATE=', self.wrapper)
        self.assertIn('export ARTIFACTS_DIR="$QUARANTINED_CANDIDATE"', self.wrapper)
        self.assertIn('RENAME_EXCL', self.wrapper)
        self.assertIn('refusing to overwrite concurrently published TODAY research candidate', self.wrapper)
        self.assertIn('QUARANTINE_OWNED=1', self.wrapper)
        self.assertIn('rm -rf "$QUARANTINED_CANDIDATE"', self.wrapper)
        self.assertLess(
            self.wrapper.index('export ARTIFACTS_DIR="$QUARANTINED_CANDIDATE"'),
            self.wrapper.index('"$CANONICAL_PRODUCER" "$@"'),
        )
        self.assertLess(
            self.wrapper.index('condition_pattern.search(line)'),
            self.wrapper.index('rename_exclusive(source, destination'),
        )

    def test_compile_proof_is_bound_to_actual_package_target_and_retained_archive_evidence(self):
        self.assertIn("xcodebuild-archive.log", self.wrapper)
        self.assertIn('module = "NembraBluetoothCapture"', self.wrapper)
        self.assertIn('condition = "NEMBRA_ES80_TODAY_RESEARCH"', self.wrapper)
        self.assertIn('if module not in line or condition not in line:', self.wrapper)
        self.assertIn('if "swift" not in line.lower():', self.wrapper)
        self.assertIn('condition_pattern.search(line)', self.wrapper)
        self.assertIn('proof_source=logs/xcodebuild-archive.log', self.wrapper)
        self.assertIn('authority=compile-capability-evidence-not-physical-authorization', self.wrapper)

    def test_ordinary_signed_producer_remains_non_authorizing(self):
        # Only the dedicated TODAY entry point may introduce this compile capability. The canonical
        # producer remains reusable for ordinary signed Release production and does not name the flag.
        self.assertNotIn("NEMBRA_ES80_TODAY_RESEARCH", self.producer)


if __name__ == "__main__":
    unittest.main()
