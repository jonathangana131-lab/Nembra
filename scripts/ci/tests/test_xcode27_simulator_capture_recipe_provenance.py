#!/usr/bin/env python3
from pathlib import Path
import plistlib
import unittest

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SIMULATOR_CAPTURE = REPOSITORY_ROOT / "scripts" / "ci" / "xcode27_simulator_capture.sh"
INFO_PLIST = REPOSITORY_ROOT / "NembraApp" / "Info.plist"
NEMBRA_APP = REPOSITORY_ROOT / "NembraApp" / "App" / "NembraApp.swift"


class SimulatorCaptureRecipeProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.capture_source = SIMULATOR_CAPTURE.read_text(encoding="utf-8")
        self.info_plist = plistlib.loads(INFO_PLIST.read_bytes())
        self.app_source = NEMBRA_APP.read_text(encoding="utf-8")

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

    def test_explicit_debug_simulator_qa_route_precedes_embedded_field_recipe(self):
        qa_guard = 'if arguments.contains("--es80-passive-capture-simulator-qa") {'
        field_recipe_guard = (
            "if let fieldRecipe = infoDictionary[captureFieldRecipeInfoPlistKey] as? String,"
        )
        qa_return = "return .es80PassiveCaptureSimulatorQA(scenario.rawValue)"
        field_return = "return .es80PassiveCapture"

        self.assertIn("#if DEBUG && targetEnvironment(simulator)", self.app_source)
        self.assertIn(qa_guard, self.app_source)
        self.assertIn(field_recipe_guard, self.app_source)
        self.assertIn(qa_return, self.app_source)
        self.assertIn(field_return, self.app_source)
        self.assertLess(self.app_source.index(qa_guard), self.app_source.index(field_recipe_guard))
        self.assertLess(self.app_source.index(qa_return), self.app_source.index(field_recipe_guard))

    def test_standard_debug_simulator_request_precedes_embedded_field_recipe(self):
        resolution_switch = "switch ScooterSimulationConfiguration.resolve("
        selected_or_invalid = "case .selected, .invalid:"
        field_recipe_guard = (
            "if let fieldRecipe = infoDictionary[captureFieldRecipeInfoPlistKey] as? String,"
        )

        self.assertIn(
            'SIMCTL_CHILD_NEMBRA_SIMULATION_SCENARIO="$state"',
            self.capture_source,
        )
        self.assertIn(resolution_switch, self.app_source)
        self.assertIn(selected_or_invalid, self.app_source)
        switch_index = self.app_source.index(resolution_switch)
        selected_or_invalid_index = self.app_source.index(selected_or_invalid, switch_index)
        standard_return_index = self.app_source.index("return .standard", selected_or_invalid_index)
        field_recipe_guard_index = self.app_source.index(field_recipe_guard)
        self.assertLess(switch_index, field_recipe_guard_index)
        self.assertLess(selected_or_invalid_index, field_recipe_guard_index)
        self.assertLess(standard_return_index, field_recipe_guard_index)

    def test_invalid_explicit_simulator_request_cannot_fall_through_to_field_capture(self):
        resolution_switch = "switch ScooterSimulationConfiguration.resolve("
        invalid_fail_closed = "case .selected, .invalid:"
        disabled_falls_through = "case .disabled:"
        field_recipe_guard = (
            "if let fieldRecipe = infoDictionary[captureFieldRecipeInfoPlistKey] as? String,"
        )

        switch_index = self.app_source.index(resolution_switch)
        invalid_index = self.app_source.index(invalid_fail_closed, switch_index)
        standard_return_index = self.app_source.index("return .standard", invalid_index)
        disabled_index = self.app_source.index(disabled_falls_through, standard_return_index)
        field_recipe_index = self.app_source.index(field_recipe_guard)

        self.assertLess(switch_index, invalid_index)
        self.assertLess(invalid_index, standard_return_index)
        self.assertLess(standard_return_index, disabled_index)
        self.assertLess(disabled_index, field_recipe_index)

    def test_external_record_uses_the_same_recipe_authority(self):
        self.assertIn('"$CAPTURE_RECIPE_IDENTIFIER" \\', self.capture_source)
        self.assertIn('"experimentRecipeID": recipe_identifier,', self.capture_source)


if __name__ == "__main__":
    unittest.main()
