#!/usr/bin/env python3
from pathlib import Path
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
WRAPPER = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"


class SignedFieldCandidateBuildSettingAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.producer = PRODUCER.read_text(encoding="utf-8")
        self.wrapper = WRAPPER.read_text(encoding="utf-8")

    def test_producer_scrubs_ambient_xcode_and_swift_authority_before_children(self):
        scrub = "unset XCODE_XCCONFIG_FILE OTHER_SWIFT_FLAGS SWIFT_ACTIVE_COMPILATION_CONDITIONS"
        self.assertIn(scrub, self.producer)
        self.assertLess(self.producer.index(scrub), self.producer.index('PYTHON3="/usr/bin/python3"'))
        self.assertLess(self.producer.index(scrub), self.producer.index('/usr/bin/stat'))
        self.assertIn('unset BASH_ENV ENV', self.producer)

    def test_legacy_research_mode_flag_is_rejected_before_child_process_authority(self):
        flag_gate = 'if [[ "${1:-}" == "--nembra-today-research-build" ]]; then'
        self.assertIn(flag_gate, self.producer)
        gate_start = self.producer.index(flag_gate)
        gate_end = self.producer.index('TODAY_RESEARCH_BUILD_MODE=0', gate_start)
        gate = self.producer[gate_start:gate_end]

        self.assertIn("SUPERSEDED: --nembra-today-research-build cannot authorize the current Capture procedure.", gate)
        self.assertIn("ES80-AUTHENTICATED-STATIONARY-v1", gate)
        self.assertIn("exit 64", gate)
        self.assertLess(gate_start, self.producer.index('PYTHON3="/usr/bin/python3"'))
        self.assertIn('TODAY_RESEARCH_BUILD_MODE=0', self.producer)
        self.assertNotIn('TODAY_RESEARCH_BUILD_MODE=1', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_MODE="private-today-v1"', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_AUTHORITY="explicit-producer-mode"', self.producer)

    def test_dormant_archive_branch_has_no_source_owned_activation_path(self):
        controlled = "'OTHER_SWIFT_FLAGS=$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH'"
        self.assertEqual(self.producer.count(controlled), 1)
        self.assertIn('run_archive_xcodebuild()', self.producer)
        self.assertIn('if [[ "$TODAY_RESEARCH_BUILD_MODE" == "1" ]]; then', self.producer)
        self.assertIn('run_xcodebuild "$@" archive', self.producer)
        self.assertNotIn('TODAY_RESEARCH_BUILD_MODE=1', self.producer)

    def test_export_path_never_receives_research_compiler_settings(self):
        export_start = self.producer.index('if ! run_xcodebuild \\\n  -exportArchive')
        export_end = self.producer.index('then', export_start)
        export_block = self.producer[export_start:export_end]
        self.assertNotIn('NEMBRA_ES80_TODAY_RESEARCH', export_block)
        self.assertNotIn('OTHER_SWIFT_FLAGS', export_block)

    def test_candidate_provenance_records_only_non_authorizing_standard_compile_state(self):
        self.assertIn('research_compile_mode=$RESEARCH_COMPILE_MODE', self.producer)
        self.assertIn('research_compile_authority=$RESEARCH_COMPILE_AUTHORITY', self.producer)
        self.assertIn('research_compile_condition=$RESEARCH_COMPILE_CONDITION', self.producer)
        self.assertIn('RESEARCH_COMPILE_MODE="standard"', self.producer)
        self.assertIn('RESEARCH_COMPILE_AUTHORITY="none"', self.producer)
        self.assertIn('RESEARCH_COMPILE_CONDITION="none"', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_MODE="private-today-v1"', self.producer)
        self.assertIn('physical_authorization=not-granted', self.producer)

    def test_today_wrapper_cannot_reintroduce_retired_build_setting_or_producer_authority(self):
        self.assertIn("SUPERSEDED: the private TODAY ES80-FINGERPRINT-v1 Research candidate path is retired.", self.wrapper)
        self.assertIn("Current Capture field procedure is ES80-AUTHENTICATED-STATIONARY-v1.", self.wrapper)
        self.assertIn("PHYSICAL NO-GO", self.wrapper)
        self.assertIn("exit 64", self.wrapper)
        self.assertNotIn('--nembra-today-research-build', self.wrapper)
        self.assertNotIn('CANONICAL_PRODUCER=', self.wrapper)
        self.assertNotIn('exec "$CANONICAL_PRODUCER"', self.wrapper)
        self.assertNotIn('export XCODE_XCCONFIG_FILE=', self.wrapper)
        self.assertNotIn('export OTHER_SWIFT_FLAGS=', self.wrapper)
        self.assertNotIn('export SWIFT_ACTIVE_COMPILATION_CONDITIONS=', self.wrapper)
        self.assertNotIn('mktemp', self.wrapper)
        self.assertNotIn('NembraES80TodayResearch.xcconfig', self.wrapper)


if __name__ == "__main__":
    unittest.main()
