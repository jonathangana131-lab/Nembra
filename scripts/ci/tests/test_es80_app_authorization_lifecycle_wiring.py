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
        # Lifecycle admissions are useless if the installed app never advances the retained manifest
        # and signed envelope through the package-owned one-shot session. Presence is never authority;
        # the entrypoint must consume the controller's verified handoff seam and gate OFF1 on `.armed`.
        self.assertIn("advanceInboxHandoffIfAvailable()", self.app)
        self.assertIn("fieldAuthorization.stage == .armed", self.app)
        handoff = self.app.index("advanceInboxHandoffIfAvailable()")
        off1 = self.app.index("admitOFF1Start()")
        self.assertLess(handoff, off1)

    def test_non_authorizing_handoff_bootstrap_does_not_require_legacy_field_authority(self) -> None:
        # `isAuthoritativeFieldBuild` is intentionally hard false until the independently signed
        # package session becomes the trust root. Requiring that legacy Boolean before reading the
        # retained manifest/challenge handoff makes the external authorization impossible to obtain.
        # Complete self-described build metadata may gate this *non-authorizing* bootstrap only;
        # `AuthenticatedStationaryCaptureAppSession.acceptEnvelope` still owns actual authority.
        handoff = self.section(
            "func advanceFieldAuthorizationHandoffIfAvailable()",
            "func activateMembershipRequestsForView()",
        )
        self.assertNotIn("buildIdentity.isAuthoritativeFieldBuild", handoff)
        self.assertIn("buildIdentity.hasCompleteFieldBuildMetadata", handoff)
        self.assertIn("advanceInboxHandoffIfAvailable()", handoff)

    def test_off1_composition_does_not_recheck_permanently_false_legacy_build_authority(self) -> None:
        # A verified `.armed` package session is the external attempt authority. The OFF1 admission
        # itself is still mandatory and fail-closed; a second hard-false bundle Boolean must not
        # make an independently signed, runtime-cross-bound session unreachable.
        section = self.section(
            "private func beginBaselineAfterCurrentOperatorAttestation()",
            "private func beginCorrelationSeries()",
        )
        self.assertNotIn("buildIdentity.isAuthoritativeFieldBuild", section)
        self.assertIn("admitOFF1Start()", section)

    def test_selected_authentication_action_is_not_gated_by_pre_off1_armed_readiness(self) -> None:
        # OFF1 legitimately advances the package stage `.armed -> .off1Started`. The selected-state
        # button must therefore not reuse the pre-OFF1 readiness Boolean that is true only at
        # `.armed`, otherwise `authenticate()` can never advance to `.authenticationAdmitted`.
        panel = self.section(
            "private var secureObservationPanel: some View",
            "private var failureRecoveryContextPanel: some View",
        )
        selected_end = panel.index("} else if test.phase == .authenticating")
        selected = panel[:selected_end]
        self.assertIn("test.authenticate()", selected)
        self.assertNotIn(".disabled(!authorityReady", selected)

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

        inline_freeze = section.find("ExactByteArtifactSeal(sealing:")
        helper_call = section.find("freezeAcceptedArtifactForAuthorizationSeal(")
        self.assertTrue(
            inline_freeze >= 0 or helper_call >= 0,
            "authorization seal must follow an exact immutable-artifact freeze boundary",
        )
        freeze = inline_freeze if inline_freeze >= 0 else helper_call
        self.assertLess(package_seal, freeze)
        self.assertLess(freeze, authority_seal)
        self.assertLess(authority_seal, accepted)

        if inline_freeze >= 0:
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
