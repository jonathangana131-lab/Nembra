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

    def test_private_research_compile_condition_has_one_explicit_source_owned_path(self):
        self.assertIn(
            'if [[ "${1:-}" == "--nembra-today-research-build" ]]; then',
            self.producer,
        )
        self.assertIn('TODAY_RESEARCH_BUILD_MODE=1', self.producer)
        controlled = "'OTHER_SWIFT_FLAGS=$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH'"
        self.assertEqual(self.producer.count(controlled), 1)
        self.assertIn('run_archive_xcodebuild()', self.producer)
        self.assertIn('run_xcodebuild "$@" archive', self.producer)
        self.assertIn(
            'run_xcodebuild "$@" \'OTHER_SWIFT_FLAGS=$(inherited) -DNEMBRA_ES80_TODAY_RESEARCH\' archive',
            self.producer,
        )

    def test_export_path_never_receives_research_compiler_settings(self):
        export_start = self.producer.index('if ! run_xcodebuild \\\n  -exportArchive')
        export_end = self.producer.index('then', export_start)
        export_block = self.producer[export_start:export_end]
        self.assertNotIn('NEMBRA_ES80_TODAY_RESEARCH', export_block)
        self.assertNotIn('OTHER_SWIFT_FLAGS', export_block)

    def test_candidate_provenance_records_compile_mode_without_granting_physical_authority(self):
        self.assertIn('research_compile_mode=$RESEARCH_COMPILE_MODE', self.producer)
        self.assertIn('research_compile_authority=$RESEARCH_COMPILE_AUTHORITY', self.producer)
        self.assertIn('research_compile_condition=$RESEARCH_COMPILE_CONDITION', self.producer)
        self.assertIn('RESEARCH_COMPILE_MODE="private-today-v1"', self.producer)
        self.assertIn('RESEARCH_COMPILE_MODE="standard"', self.producer)
        self.assertIn('physical_authorization=not-granted', self.producer)

    def test_today_wrapper_cannot_reintroduce_ambient_xcconfig_authority(self):
        self.assertIn(
            'exec "$CANONICAL_PRODUCER" --nembra-today-research-build "$@"',
            self.wrapper,
        )
        self.assertIn(
            'unset SWIFT_ACTIVE_COMPILATION_CONDITIONS OTHER_SWIFT_FLAGS XCODE_XCCONFIG_FILE',
            self.wrapper,
        )
        self.assertNotIn('export XCODE_XCCONFIG_FILE=', self.wrapper)
        self.assertNotIn('mktemp', self.wrapper)
        self.assertNotIn('NembraES80TodayResearch.xcconfig', self.wrapper)


if __name__ == "__main__":
    unittest.main()
