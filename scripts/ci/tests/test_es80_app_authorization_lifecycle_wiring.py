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
        self.assertTrue(any(marker in context for marker in (
            "failLocally(", "failAndRetireSession(", "invalidateInternalLifecycle(", "retireSession",
        )))

    def test_standalone_target_compiles_thin_app_authorization_controller(self) -> None:
        self.assertIn("NembraCaptureFieldAuthorizationController.swift in Sources", self.project)
        self.assertIn("NembraCaptureAppAuthorization in Frameworks", self.project)
        self.assertIn("AuthenticatedStationaryCaptureAppSession", self.controller)

    def test_secure_link_owns_one_authorization_controller(self) -> None:
        self.assertIn("NembraCaptureFieldAuthorizationController", self.app)
        self.assertIn("fieldAuthorization", self.app)

    def test_real_entrypoint_drives_handoff_to_armed_before_off1(self) -> None:
        handoff = self.app.index("advanceInboxHandoffIfAvailable()")
        off1 = self.app.index("admitOFF1Start()")
        self.assertLess(handoff, off1)
        self.assertIn("fieldAuthorization.stage == .armed", self.app)

    def test_off1_requires_authorization_before_correlation(self) -> None:
        # Current main performs its fresh account/device verification directly in startBaseline().
        # The one-time authorization admission must remain inside that same path immediately
        # before the package-owned OFF1 correlation series begins.
        section = self.section("func startBaseline()", "private func beginCorrelationSeries()")
        admission = section.index("admitOFF1Start()")
        self.assertLess(admission, section.index("beginCorrelationSeries()"))
        self.assert_fail_closed_near(section, "admitOFF1Start()")

    def test_authentication_requires_authorization_before_connection(self) -> None:
        section = self.section("func authenticate()", "private func beginOfficialConnection(candidate: Candidate)")
        self.assertIn("admitAuthenticationStart()", section)
        self.assert_fail_closed_near(section, "admitAuthenticationStart()")

    def test_official_connection_requires_authorization_before_driver_creation(self) -> None:
        section = self.section("private func beginOfficialConnection(candidate: Candidate)", "private func authenticated(token: TuyaReadOnlyConnectionToken)")
        admission = section.index("admitOfficialConnectionStart()")
        self.assertLess(admission, section.index("OfficialTuyaFactory.make()"))
        self.assertLess(admission, section.index("newDriver.connect("))
        self.assert_fail_closed_near(section, "admitOfficialConnectionStart()")

    def test_observation_requires_authorization_before_observing_state(self) -> None:
        section = self.section("private func authenticated(token: TuyaReadOnlyConnectionToken)", "private func authenticationFailed(token: TuyaReadOnlyConnectionToken)")
        admission = section.index("admitObservationStart()")
        self.assertLess(admission, section.index("phase = .observing"))
        self.assert_fail_closed_near(section, "admitObservationStart()")

    def test_capability_seals_only_after_exact_accepted_bytes_are_frozen_and_verified(self) -> None:
        section = self.section("private func startWatchdog(token: TuyaReadOnlyConnectionToken)", "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)")
        package_seal = section.index("sealAcceptedObservation(for: token)")
        freeze_call = section.index("try self.freezeAcceptedArtifactForAuthorizationSeal()")
        authority_seal = section.index("try self.fieldAuthorization.sealAfterAcceptedArtifactFreeze()")
        accepted = section.index("self.phase = .accepted")
        self.assertLess(package_seal, freeze_call)
        self.assertLess(freeze_call, authority_seal)
        self.assertLess(authority_seal, accepted)

        # Do not use a proximity window here: the accepted-artifact error handling is deliberately
        # verbose. Prove the exact operational do/catch block structurally instead.
        do_start = section.rfind("do {", package_seal, freeze_call)
        catch_start = section.index("} catch {", authority_seal)
        success_status = section.index(
            'self.fieldAuthorizationStatus = "One-time field authorization sealed with the verified accepted artifact."',
            catch_start,
        )
        self.assertGreaterEqual(do_start, 0)
        guarded = section[do_start:success_status]
        for required in (
            "do {",
            "try self.freezeAcceptedArtifactForAuthorizationSeal()",
            "try self.fieldAuthorization.sealAfterAcceptedArtifactFreeze()",
            "} catch {",
            "self.fieldAuthorization.revoke()",
            "self.sealedAcceptedExport = nil",
            "self.exportData = nil",
            "self.phase = .failed",
            "return",
        ):
            self.assertIn(required, guarded)

        helper = self.section(
            "private func freezeAcceptedArtifactForAuthorizationSeal() throws",
            "private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
        )
        for required in (
            "ExactByteArtifactSeal(sealing: exactBytes)",
            "try artifactSeal.verifiedBytes()",
            "artifactSeal.verifies(verifiedBytes)",
            "self.exportData = verifiedBytes",
        ):
            self.assertIn(required, helper)

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
        view_exit = self.section("func abandonCorrelationForViewExit()", "func appDidLoseForeground()")
        self.assertIn("fieldAuthorization.revoke()", foreground)
        self.assertIn("fieldAuthorization.revoke()", view_exit)


if __name__ == "__main__":
    unittest.main()
