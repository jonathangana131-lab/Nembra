#!/usr/bin/env python3
from pathlib import Path
import unittest

PRODUCER = Path(__file__).resolve().parents[1] / "xcode27_signed_field_candidate.sh"
WRAPPER = Path(__file__).resolve().parents[1] / "xcode27_today_research_field_candidate.sh"
CURRENT_PROCEDURE = "ES80-AUTHENTICATED-STATIONARY-v1"
RETIRED_MODE = "--nembra-today-research-build"


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

    def test_retired_private_research_compile_mode_fails_before_archive_authority(self):
        admission = f'if [[ "${{1:-}}" == "{RETIRED_MODE}" ]]; then'
        self.assertIn(admission, self.producer)
        block_start = self.producer.index(admission)
        block_end = self.producer.index('fi', block_start)
        block = self.producer[block_start:block_end]
        self.assertIn('SUPERSEDED:', block)
        self.assertIn(CURRENT_PROCEDURE, block)
        self.assertIn('scripts/field/install_one_time_capture.command', block)
        self.assertIn('exit 64', block)

        self.assertNotIn('TODAY_RESEARCH_BUILD_MODE=1', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_MODE="private-today-v1"', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_AUTHORITY="canonical-producer-explicit-mode"', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_CONDITION="NEMBRA_ES80_TODAY_RESEARCH"', self.producer)
        self.assertIn('TODAY_RESEARCH_BUILD_MODE=0', self.producer)
        self.assertIn('RESEARCH_COMPILE_MODE="standard"', self.producer)
        self.assertIn('RESEARCH_COMPILE_AUTHORITY="none"', self.producer)
        self.assertIn('RESEARCH_COMPILE_CONDITION="none"', self.producer)

    def test_export_path_never_receives_research_compiler_settings(self):
        export_start = self.producer.index('if ! run_xcodebuild \\\n  -exportArchive')
        export_end = self.producer.index('then', export_start)
        export_block = self.producer[export_start:export_end]
        self.assertNotIn('NEMBRA_ES80_TODAY_RESEARCH', export_block)
        self.assertNotIn('OTHER_SWIFT_FLAGS', export_block)

    def test_candidate_provenance_records_only_non_authorizing_standard_compile_mode(self):
        self.assertIn('research_compile_mode=$RESEARCH_COMPILE_MODE', self.producer)
        self.assertIn('research_compile_authority=$RESEARCH_COMPILE_AUTHORITY', self.producer)
        self.assertIn('research_compile_condition=$RESEARCH_COMPILE_CONDITION', self.producer)
        self.assertIn('RESEARCH_COMPILE_MODE="standard"', self.producer)
        self.assertIn('RESEARCH_COMPILE_AUTHORITY="none"', self.producer)
        self.assertIn('RESEARCH_COMPILE_CONDITION="none"', self.producer)
        self.assertNotIn('RESEARCH_COMPILE_MODE="private-today-v1"', self.producer)
        self.assertIn('physical_authorization=not-granted', self.producer)

    def test_retired_today_wrapper_cannot_delegate_or_reintroduce_build_authority(self):
        self.assertIn('SUPERSEDED:', self.wrapper)
        self.assertIn(CURRENT_PROCEDURE, self.wrapper)
        self.assertIn('scripts/field/install_one_time_capture.command', self.wrapper)
        self.assertIn('exit 64', self.wrapper)
        self.assertNotIn('CANONICAL_PRODUCER=', self.wrapper)
        self.assertNotIn('exec "$CANONICAL_PRODUCER"', self.wrapper)
        self.assertNotIn('export XCODE_XCCONFIG_FILE=', self.wrapper)
        self.assertNotIn('export OTHER_SWIFT_FLAGS=', self.wrapper)
        self.assertNotIn('export SWIFT_ACTIVE_COMPILATION_CONDITIONS=', self.wrapper)
        self.assertNotIn('mktemp', self.wrapper)
        self.assertNotIn('NembraES80TodayResearch.xcconfig', self.wrapper)


if __name__ == "__main__":
    unittest.main()
