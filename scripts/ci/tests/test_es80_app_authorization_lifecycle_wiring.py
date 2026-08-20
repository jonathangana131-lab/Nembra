from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PROJECT = ROOT / "NembraCapture.xcodeproj/project.pbxproj"
CONTROLLER = ROOT / "NembraApp/App/NembraCaptureFieldAuthorizationController.swift"


class AppAuthorizationLifecycleWiringTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = APP.read_text(encoding="utf-8")
        cls.project = PROJECT.read_text(encoding="utf-8")
        cls.controller = CONTROLLER.read_text(encoding="utf-8")

    def section(self, start: str, end: str) -> str:
        start_index = self.app.index(start)
        end_index = self.app.index(end, start_index + len(start))
        return self.app[start_index:end_index]

    def assert_fail_closed_near(self, section: str, needle: str) -> None:
        index = section.index(needle)
        context = section[max(0, index - 1000): index + 1000]
        self.assertIn("do {", context)
        self.assertIn("catch", context)
        self.assertTrue(
            any(marker in context for marker in (
                "failLocally(",
                "failAndRetireSession(",
                "invalidateInternalLifecycle(",
                "retireSession",
            )),
            f"{needle} is not surrounded by fail-closed lifecycle handling",
        )

    def test_standalone_target_compiles_thin_app_authorization_controller(self) -> None:
        self.assertIn("NembraCaptureFieldAuthorizationController.swift in Sources", self.project)
        self.assertIn("NembraCaptureAppAuthorization in Frameworks", self.project)
        self.assertIn("AuthenticatedStationaryCaptureAppSession", self.controller)
        self.assertNotIn("AuthenticatedStationaryCaptureCapabilityGate?", self.controller)
        self.assertNotIn("AuthenticatedStationaryCaptureAppAuthorizer", self.controller)

    def test_secure_link_owns_one_authorization_controller(self) -> None:
        self.assertIn("NembraCaptureFieldAuthorizationController", self.app)
        self.assertIn("fieldAuthorization", self.app)

    def test_real_entrypoint_drives_handoff_to_armed_before_off1(self) -> None:
        self.assertIn("advanceInboxHandoffIfAvailable()", self.app)
        self.assertIn("fieldAuthorization.stage == .armed", self.app)
        handoff = self.app.index("advanceInboxHandoffIfAvailable()")
        off1 = self.app.index("admitOFF1Start()")
        self.assertLess(handoff, off1)

    def test_off1_requires_authorization_before_correlation(self) -> None:
        section = self.section(
            "private func beginBaselineAfterCurrentOperatorAttestation()",
            "private func beginCorrelationSeries()",
        )
        admission = section.index("admitOFF1Start()")
        correlation = section.index("beginCorrelationSeries()")
        self.assertLess(admission, correlation)
        self.assert_fail_closed_near(section, "admitOFF1Start()")

    def test_failed_retry_requires_fresh_armed_authorization(self) -> None:
        retry = self.section(
            "var failedAttemptCanRestartFromOFF1: Bool",
            "var canRestartFromFreshOFF1: Bool",
        )
        self.assertIn("fieldAuthorization.stage == .armed", retry)

    def test_failed_transition_preserves_only_unspent_armed_authorization(self) -> None:
        failed = self.section(
            "if phase == .failed {",
            "operatorSafetyAttemptID = nil",
        )
        self.assertIn("fieldAuthorization.stage != .armed", failed)
        self.assertIn("fieldAuthorization.revoke()", failed)
        self.assertLess(
            failed.index("fieldAuthorization.stage != .armed"),
            failed.index("fieldAuthorization.revoke()"),
        )

    def test_authentication_requires_authorization_before_connection(self) -> None:
        section = self.section(
            "func authenticate()",
            "private func beginOfficialConnection(candidate: Candidate)",
        )
        self.assertIn("admitAuthenticationStart()", section)
        self.assert_fail_closed_near(section, "admitAuthenticationStart()")

    def test_official_connection_requires_authorization_before_driver_creation(self) -> None:
        section = self.section(
            "private func beginOfficialConnection(candidate: Candidate)",
            "private func authenticated(token: TuyaReadOnlyConnectionToken)",
        )
        admission = section.index("admitOfficialConnectionStart()")
        self.assertLess(admission, section.index("OfficialTuyaFactory.make()"))
        self.assertLess(admission, section.index("newDriver.connect("))
        self.assert_fail_closed_near(section, "admitOfficialConnectionStart()")

    def test_observation_requires_authorization_before_observing_state(self) -> None:
        section = self.section(
            "private func authenticated(token: TuyaReadOnlyConnectionToken)",
            "private func authenticationFailed(token: TuyaReadOnlyConnectionToken)",
        )
        admission = section.index("admitObservationStart()")
        self.assertLess(admission, section.index("phase = .observing"))
        self.assert_fail_closed_near(section, "admitObservationStart()")

    def test_capability_seals_only_after_exact_accepted_bytes_are_frozen_and_verified(self) -> None:
        section = self.section(
            "private func startWatchdog(token: TuyaReadOnlyConnectionToken)",
            "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
        )
        package_seal = section.index("sealAcceptedObservation(for: token)")
        authority_seal = section.index("sealAfterAcceptedArtifactFreeze()")
        accepted = section.index("self.phase = .accepted")

        # The helper implementation itself can live later in this same textual section. Treat
        # ExactByteArtifactSeal(...) as an inline freeze only when it occurs before the authority
        # seal call; otherwise validate the earlier helper call and inspect the helper body below.
        inline_freeze = section.find("ExactByteArtifactSeal(sealing:")
        helper_call = section.find("freezeAcceptedArtifactForAuthorizationSeal(")
        inline_freeze_before_authority_seal = 0 <= inline_freeze < authority_seal
        self.assertTrue(
            inline_freeze_before_authority_seal or helper_call >= 0,
            "authorization seal must follow an exact immutable-artifact freeze boundary",
        )
        freeze = inline_freeze if inline_freeze_before_authority_seal else helper_call
        self.assertLess(package_seal, freeze)
        self.assertLess(freeze, authority_seal)
        self.assertLess(authority_seal, accepted)

        if inline_freeze_before_authority_seal:
            between = section[inline_freeze:authority_seal]
            self.assertIn(".verifies(", between)
            self.assertTrue(
                "verifiedBytes()" in between or "verifiedCanonicalValue(" in between,
                "exact bytes must be canonically verified before authorization seal",
            )
        else:
            helper_start = self.app.index("private func freezeAcceptedArtifactForAuthorizationSeal(")
            helper_end_candidates = [
                self.app.find("private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)", helper_start),
                self.app.find("private func invalidateSourceAuthority(", helper_start),
            ]
            helper_end_candidates = [value for value in helper_end_candidates if value >= 0]
            self.assertTrue(helper_end_candidates)
            helper = self.app[helper_start:min(helper_end_candidates)]
            self.assertIn("ExactByteArtifactSeal(sealing:", helper)
            self.assertIn(".verifies(", helper)
            self.assertTrue(
                "verifiedBytes()" in helper or "verifiedCanonicalValue(" in helper,
                "artifact-freeze helper must prove canonical bytes before returning",
            )

        self.assert_fail_closed_near(section, "sealAfterAcceptedArtifactFreeze()")

    def test_authority_admissions_cannot_be_optional_noops(self) -> None:
        for forbidden in (
            "fieldAuthorization?.admitOFF1Start()",
            "fieldAuthorization?.admitAuthenticationStart()",
            "fieldAuthorization?.admitOfficialConnectionStart()",
            "fieldAuthorization?.admitObservationStart()",
            "fieldAuthorization?.sealAfterAcceptedArtifactFreeze()",
        ):
            self.assertNotIn(forbidden, self.app)

    def test_foreground_and_view_abandonment_revoke_unfinished_authority(self) -> None:
        foreground = self.section("func appDidLoseForeground()", "var privateConfig: Bool")
        view_exit = self.section(
            "func abandonCorrelationForViewExit()",
            "func appDidLoseForeground()",
        )
        self.assertIn("fieldAuthorization.revoke()", foreground)
        self.assertIn("fieldAuthorization.revoke()", view_exit)


if __name__ == "__main__":
    unittest.main()
