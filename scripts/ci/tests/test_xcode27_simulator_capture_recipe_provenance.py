#!/usr/bin/env python3
from pathlib import Path
import plistlib
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SIMULATOR_CAPTURE = REPOSITORY_ROOT / "scripts" / "ci" / "xcode27_simulator_capture.sh"
INFO_PLIST = REPOSITORY_ROOT / "NembraApp" / "Info.plist"


class SimulatorCaptureRecipeProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.capture_source = SIMULATOR_CAPTURE.read_text(encoding="utf-8")
        self.info_plist = plistlib.loads(INFO_PLIST.read_bytes())

    def test_recipe_is_one_explicit_build_setting_and_retained_plist_subject(self):
        self.assertEqual(
            self.info_plist.get("NembraCaptureFieldRecipe"),
            "$(NEMBRA_CAPTURE_FIELD_RECIPE)",
        )
        self.assertIn('CAPTURE_RECIPE_IDENTIFIER="ES80-FINGERPRINT-v1"', self.capture_source)
        self.assertIn(
            '"NEMBRA_CAPTURE_FIELD_RECIPE=$CAPTURE_RECIPE_IDENTIFIER"',
            self.capture_source,
        )
        self.assertIn(
            "EMBEDDED_FIELD_RECIPE=\"$(/usr/libexec/PlistBuddy -c 'Print :NembraCaptureFieldRecipe' \"$INFO_PLIST\" 2>/dev/null || true)\"",
            self.capture_source,
        )
        self.assertIn(
            'if [[ "$EMBEDDED_FIELD_RECIPE" != "$CAPTURE_RECIPE_IDENTIFIER" ]]; then',
            self.capture_source,
        )
        self.assertIn(
            'echo "Built app did not preserve the exact Capture experiment recipe." >&2',
            self.capture_source,
        )

    def test_external_record_uses_the_same_recipe_authority(self):
        self.assertIn('"$CAPTURE_RECIPE_IDENTIFIER" \\', self.capture_source)
        self.assertIn('"experimentRecipeID": recipe_identifier,', self.capture_source)


if __name__ == "__main__":
    unittest.main()
