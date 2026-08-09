from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
DASHBOARD = ROOT / "NembraApp/Features/Dashboard/DashboardView.swift"


class DashboardStoppedControlTruthTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = DASHBOARD.read_text(encoding="utf-8")

    def test_stopped_authority_requires_real_finite_nonnegative_speed(self) -> None:
        source = self.source
        self.assertIn("enum DashboardStoppedControlPresentation: Equatable", source)
        self.assertIn("guard connection == .connected else { return .hidden }", source)
        self.assertRegex(
            source,
            re.compile(
                r"guard let speedKilometersPerHour,\s*"
                r"speedKilometersPerHour\.isFinite,\s*"
                r"speedKilometersPerHour >= 0 else \{\s*"
                r"return \.awaitingLiveSpeed\s*\}",
                re.MULTILINE,
            ),
        )
        self.assertIn(
            "return speedKilometersPerHour < 0.5 ? .controls : .moving",
            source,
        )

    def test_dashboard_never_turns_unknown_speed_into_zero_for_control_visibility(self) -> None:
        source = self.source
        self.assertNotIn("speedKilometersPerHour ?? 0", source)
        self.assertIn("case .awaitingLiveSpeed:", source)
        self.assertIn('Label("Waiting for live speed", systemImage: "waveform.slash")', source)
        self.assertIn('.accessibilityValue("Waiting for confirmed live speed")', source)

    def test_view_binds_policy_to_confirmed_vehicle_state(self) -> None:
        source = self.source
        self.assertRegex(
            source,
            re.compile(
                r"private var stoppedControlPresentation: DashboardStoppedControlPresentation \{\s*"
                r"DashboardStoppedControlPresentation\.resolved\(\s*"
                r"connection: vehicle\.state\.connection,\s*"
                r"speedKilometersPerHour: vehicle\.state\.speedKilometersPerHour\s*"
                r"\)\s*\}",
                re.MULTILINE,
            ),
        )
        self.assertIn("switch stoppedControlPresentation {", source)
        self.assertIn("case .controls:", source)
        self.assertIn("case .moving:", source)
        self.assertIn("case .hidden:", source)


if __name__ == "__main__":
    unittest.main()
