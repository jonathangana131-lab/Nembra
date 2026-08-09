#!/usr/bin/env python3
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
WRAPPER = ROOT / "scripts/ci/xcode27_today_research_field_candidate.sh"
PRODUCER = ROOT / "scripts/ci/xcode27_signed_field_candidate.sh"


class TodayResearchCompileCapabilitySourceTests(unittest.TestCase):
    def setUp(self):
        self.wrapper = WRAPPER.read_text(encoding="utf-8")
        self.producer = PRODUCER.read_text(encoding="utf-8")

    @staticmethod
    def _matches_exact_package_compile(line: str) -> bool:
        module = "NembraBluetoothCapture"
        condition = "NEMBRA_ES80_TODAY_RESEARCH"
        module_pattern = re.compile(
            r"(?:^|\s)-module-name(?:\s+|=)" + re.escape(module) + r"(?:\s|$)"
        )
        condition_pattern = re.compile(
            r"(?:^|\s)-D\s*" + re.escape(condition) + r"(?:\s|$)"
        )
        return (
            module in line
            and condition in line
            and "swift" in line.lower()
            and module_pattern.search(line) is not None
            and condition_pattern.search(line) is not None
        )

    def test_today_flag_is_not_treated_as_proven_by_environment_injection_alone(self):
        self.assertIn("NEMBRA_ES80_TODAY_RESEARCH", self.wrapper)
        self.assertIn("OTHER_SWIFT_FLAGS", self.wrapper)
        self.assertIn('ARCHIVE_LOG="$QUARANTINED_CANDIDATE/logs/xcodebuild-archive.log"', self.wrapper)
        self.assertIn('module = "NembraBluetoothCapture"', self.wrapper)
        self.assertIn('condition = "NEMBRA_ES80_TODAY_RESEARCH"', self.wrapper)
        self.assertIn("module_pattern.search(line) and condition_pattern.search(line)", self.wrapper)
        self.assertIn("today_research_compile_capability=verified", self.wrapper)

    def test_candidate_cannot_report_success_before_compile_capability_proof(self):
        producer_call = self.wrapper.index('"$CANONICAL_PRODUCER" "$@"')
        archive_proof = self.wrapper.index(
            'module_pattern.search(line) and condition_pattern.search(line)'
        )
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
            self.wrapper.index('module_pattern.search(line) and condition_pattern.search(line)'),
            self.wrapper.index('rename_exclusive(source, destination'),
        )

    def test_compile_proof_requires_compiler_module_identity_not_a_name_mention(self):
        # False-green fixture: the app target carries the global flag and mentions the package only
        # as a search/import path. This must not prove that the package itself consumed the flag.
        app_target_line = (
            "/usr/bin/swiftc -module-name Nembra -I /tmp/Build/Products/Release-iphoneos/"
            "NembraBluetoothCapture.swiftmodule -D NEMBRA_ES80_TODAY_RESEARCH -c App.swift"
        )
        self.assertFalse(self._matches_exact_package_compile(app_target_line))

        package_target_line = (
            "/usr/bin/swiftc -module-name NembraBluetoothCapture "
            "-D NEMBRA_ES80_TODAY_RESEARCH -c PassiveBluetoothExperimentOneRun.swift"
        )
        self.assertTrue(self._matches_exact_package_compile(package_target_line))

        package_target_joined_define = (
            "/usr/bin/swiftc -module-name=NembraBluetoothCapture "
            "-DNEMBRA_ES80_TODAY_RESEARCH -c PassiveBluetoothExperimentOneRun.swift"
        )
        self.assertTrue(self._matches_exact_package_compile(package_target_joined_define))

    def test_compile_proof_is_bound_to_actual_package_target_and_retained_archive_evidence(self):
        self.assertIn("xcodebuild-archive.log", self.wrapper)
        self.assertIn('module = "NembraBluetoothCapture"', self.wrapper)
        self.assertIn('condition = "NEMBRA_ES80_TODAY_RESEARCH"', self.wrapper)
        self.assertIn("-module-name", self.wrapper)
        self.assertIn("module_pattern.search(line) and condition_pattern.search(line)", self.wrapper)
        self.assertIn('proof_source=logs/xcodebuild-archive.log', self.wrapper)
        self.assertIn('proof_source_sha256=$ARCHIVE_LOG_SHA256', self.wrapper)
        self.assertIn('compiler_module_name=NembraBluetoothCapture', self.wrapper)
        self.assertIn('authority=compile-capability-evidence-not-physical-authorization', self.wrapper)

    def test_ordinary_signed_producer_remains_non_authorizing(self):
        # Only the dedicated TODAY entry point may introduce this compile capability. The canonical
        # producer remains reusable for ordinary signed Release production and does not name the flag.
        self.assertNotIn("NEMBRA_ES80_TODAY_RESEARCH", self.producer)


if __name__ == "__main__":
    unittest.main()
