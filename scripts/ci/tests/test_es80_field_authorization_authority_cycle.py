from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
IDENTITY = ROOT / "NembraApp/App/NembraCaptureBuildIdentity.swift"


class FieldAuthorizationAuthorityCycleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = APP.read_text(encoding="utf-8")
        cls.identity = IDENTITY.read_text(encoding="utf-8")

    def section(self, start: str, end: str) -> str:
        start_index = self.app.index(start)
        end_index = self.app.index(end, start_index + len(start))
        return self.app[start_index:end_index]

    def test_legacy_self_authority_stays_hard_false_but_is_not_a_runtime_gate(self) -> None:
        self.assertIn(
            "var isAuthoritativeFieldBuild: Bool {\n        false\n    }",
            self.identity,
        )
        self.assertNotIn("buildIdentity.isAuthoritativeFieldBuild", self.app)
        self.assertNotIn("fieldBuildIsAuthoritative", self.app)

    def test_root_uses_metadata_only_for_non_bluetooth_account_setup(self) -> None:
        root = self.section(
            "@MainActor\nprivate struct CaptureP0Root: View",
            "@MainActor\nprivate final class SecureLinkController:",
        )
        self.assertIn(
            "private var fieldBuildMetadataReady: Bool { buildIdentity.hasCompleteFieldBuildMetadata }",
            root,
        )
        self.assertIn("if fieldBuildMetadataReady && sdkAccount.loggedIn", root)
        self.assertIn("if !fieldBuildMetadataReady {", root)
        self.assertIn("guard fieldBuildMetadataReady else { return }", root)
        self.assertIn("Build metadata ready", root)
        self.assertIn("one-time field authorization checks are still required before Bluetooth", root)
        self.assertNotIn("Field build ready", root)

    def test_non_authorizing_handoff_is_reachable_from_complete_runtime_metadata(self) -> None:
        handoff = self.section(
            "func advanceFieldAuthorizationHandoffIfAvailable()",
            "func activateMembershipRequestsForView()",
        )
        self.assertIn(
            "guard phase == .idle, buildIdentity.hasCompleteFieldBuildMetadata else { return }",
            handoff,
        )
        self.assertIn("fieldAuthorization.advanceInboxHandoffIfAvailable()", handoff)
        self.assertIn("fieldAuthorization.revoke()", handoff)

    def test_product_start_requires_metadata_and_independent_session_authority(self) -> None:
        ready = self.section(
            "private var authorityReady: Bool",
            "private var currentStageIndex: Int",
        )
        for token in (
            "test.fieldBuildMetadataReady",
            "test.fieldAuthorizationReady",
            "test.privateConfig",
            "test.sdkAccountLoggedIn",
            "test.sdkDeviceMembershipVerified",
            "test.accountIdentityLeaseIsAuthorized",
        ):
            self.assertIn(token, ready)
        self.assertIn(
            'requirementRow("Capture build metadata", ready: test.fieldBuildMetadataReady)',
            self.app,
        )
        self.assertIn(
            'requirementRow("One-time field authorization", ready: test.fieldAuthorizationReady)',
            self.app,
        )

    def test_off1_metadata_check_precedes_independent_authorization_and_scan(self) -> None:
        baseline = self.section(
            "private func beginBaselineAfterCurrentOperatorAttestation()",
            "private func beginCorrelationSeries()",
        )
        metadata = baseline.index("guard buildIdentity.hasCompleteFieldBuildMetadata else")
        admission = baseline.index("fieldAuthorization.admitOFF1Start()")
        scan = baseline.index("beginCorrelationSeries()")
        self.assertLess(metadata, admission)
        self.assertLess(admission, scan)

    def test_official_driver_cannot_exist_before_session_admission(self) -> None:
        connection = self.section(
            "private func beginOfficialConnection(candidate: Candidate)",
            "private func authenticated(token: TuyaReadOnlyConnectionToken)",
        )
        metadata = connection.index("buildIdentity.hasCompleteFieldBuildMetadata")
        admission = connection.index("fieldAuthorization.admitOfficialConnectionStart()")
        factory = connection.index("OfficialTuyaFactory.make()")
        connect = connection.index("newDriver.connect(")
        self.assertLess(metadata, admission)
        self.assertLess(admission, factory)
        self.assertLess(admission, connect)


if __name__ == "__main__":
    unittest.main()
