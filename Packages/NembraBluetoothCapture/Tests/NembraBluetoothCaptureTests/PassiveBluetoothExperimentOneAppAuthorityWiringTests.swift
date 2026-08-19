import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Authenticated stationary Capture app authority wiring")
struct PassiveBluetoothExperimentOneAppAuthorityWiringTests {
    @Test("physical field build is the standalone authenticated Capture target")
    func fieldBuildUsesStandaloneAuthenticatedCaptureTarget() throws {
        let project = try Self.repositoryFile("NembraCapture.xcodeproj/project.pbxproj")
        let installer = try Self.repositoryFile("scripts/field/install_one_time_capture.command")

        #expect(project.contains("NembraCaptureEntrypoint.swift in Sources"))
        #expect(project.contains("NembraCaptureSimulatorQAHarness.swift in Sources"))
        #expect(project.contains("NembraCaptureBuildIdentity.swift in Sources"))
        #expect(!project.contains("TuyaAccountBridge.swift"))
        #expect(!project.contains("ES80CaptureShellView.swift"))
        #expect(!project.contains("NembraApp.swift in Sources"))

        #expect(installer.contains("-workspace NembraCapture.xcworkspace"))
        #expect(installer.contains("-scheme \"Nembra Capture\""))
        #expect(installer.contains("Do not use NembraCapture.xcodeproj for the authenticated field build."))
        #expect(installer.contains("PROCEDURE_ID=\"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(!installer.contains("--nembra-today-research-build"))
        #expect(!installer.contains("NEMBRA_ES80_TODAY_RESEARCH"))
    }

    @Test("standalone entrypoint requires exact field provenance and current Tuya authority before correlation")
    func authenticatedEntrypointFailsClosedBeforeBluetoothCorrelation() throws {
        let source = try Self.repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let startBaseline = String(try Self.section(
            in: source,
            from: "    private func beginBaselineAfterCurrentOperatorAttestation() {",
            to: "    private func beginCorrelationSeries() {"
        ))
        let beginCorrelation = String(try Self.section(
            in: source,
            from: "    private func beginCorrelationSeries() {",
            to: "    func startNextCorrelationWindow() {"
        ))

        #expect(source.contains("@main @MainActor\nstruct NembraCaptureApp: App"))
        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(startBaseline.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        #expect(startBaseline.contains("guard privateConfig, sdkAccountLoggedIn else"))
        #expect(startBaseline.contains("verifySDKMembership"))
        #expect(startBaseline.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(startBaseline.contains("self.beginCorrelationSeries()"))

        #expect(beginCorrelation.contains("sdkDeviceMembershipVerified"))
        #expect(beginCorrelation.contains("accountIdentityLeaseIsAuthorized"))
        #expect(beginCorrelation.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
        #expect(beginCorrelation.contains("OfficialTuyaFactory.acquirePackageCorrelationLease()"))
        #expect(beginCorrelation.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))

        #expect(!source.contains("makeResearchAuthorizedES80ForCurrentApplication()"))
        #expect(!source.contains("PassiveBluetoothExperimentOneCoordinator.makeAuthorizedES80()"))
        #expect(!source.contains("verifiedAdmission:"))
        #expect(!source.contains("ES80ExperimentOneFieldNoGoView"))
        #expect(!source.contains("disconnectedDeclarationAccepted"))
        #expect(!source.contains("selectedChargerState"))
        #expect(!source.contains("UserDefaults"))
    }

    @Test("root selection is only context; Secure Link freshly verifies exact membership before scan and authentication")
    func secureLinkRechecksMembershipAtBothAuthorityBoundaries() throws {
        let source = try Self.repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let root = String(try Self.section(
            in: source,
            from: "@MainActor\nprivate struct CaptureP0Root: View",
            to: "@MainActor\nprivate final class SecureLinkController:"
        ))
        let start = String(try Self.section(
            in: source,
            from: "    private func beginBaselineAfterCurrentOperatorAttestation() {",
            to: "    private func beginCorrelationSeries() {"
        ))
        let authenticate = String(try Self.section(
            in: source,
            from: "    func authenticate() {",
            to: "    private func beginOfficialConnection(candidate: Candidate) {"
        ))
        let membership = String(try Self.section(
            in: source,
            from: "    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {",
            to: "    func authenticate() {"
        ))

        #expect(root.contains("SecureLinkView(device: selected, sdkAccount: sdkAccount)"))
        #expect(root.contains("fresh, complete same-account membership check immediately before Bluetooth discovery"))

        #expect(start.contains("verifySDKMembership { [weak self] authorized in"))
        #expect(start.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(start.contains("self.beginCorrelationSeries()"))

        #expect(authenticate.contains("// Membership is re-proven immediately before granting Tuya BLE ownership."))
        #expect(authenticate.contains("verifySDKMembership { [weak self] stillAuthorized in"))
        #expect(authenticate.contains("self.phase == .selected"))
        #expect(authenticate.contains("self.targetCorrelationOperatorConfirmed"))
        #expect(authenticate.contains("self.selectedID == candidate.id"))
        #expect(authenticate.contains("self.beginOfficialConnection(candidate: candidate)"))

        #expect(membership.contains("let requestID = UUID()"))
        #expect(membership.contains("membershipRequestID = requestID"))
        #expect(membership.contains("guard let self, self.membershipRequestID == requestID else { return }"))
        #expect(membership.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(membership.contains("self.membershipDeviceID = expected"))
    }

    @Test("package correlation retires before official Tuya BLE ownership and failed restart stays fenced")
    func processOwnershipAndRestartRemainFailClosed() throws {
        let source = try Self.repositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")

        let lease = try #require(source.range(of: "OfficialTuyaFactory.acquirePackageCorrelationLease()"))
        let correlation = try #require(
            source.range(of: "PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)")
        )
        let officialSDKOwnership = try #require(
            source.range(
                of: "OfficialTuyaFactory.make()",
                range: correlation.upperBound..<source.endIndex
            )
        )
        #expect(lease.lowerBound < correlation.lowerBound)
        #expect(correlation.lowerBound < officialSDKOwnership.lowerBound)

        #expect(source.contains("private var processCorrelationLease: UUID?"))
        #expect(source.contains("private var currentConnectionToken: TuyaReadOnlyConnectionToken?"))
        #expect(source.contains("private var localBLESettlementToken: TuyaReadOnlyConnectionToken?"))
        #expect(source.contains("func abandonCorrelationForViewExit()"))
        #expect(source.contains("private func releasePackageCorrelationLease()"))
        #expect(source.contains("OfficialTuyaFactory.releasePackageCorrelationLease(processCorrelationLease)"))

        let restart = String(try Self.section(
            in: source,
            from: "    var failedAttemptCanRestartFromOFF1: Bool {",
            to: "    var canRestartFromFreshOFF1: Bool"
        ))
        #expect(restart.contains("phase == .failed"))
        #expect(restart.contains("currentConnectionToken == nil"))
        #expect(restart.contains("localBLESettlementToken == nil"))
        #expect(restart.contains("driver == nil"))
        #expect(restart.contains("OfficialTuyaFactory.packageCorrelationMayStart"))
    }

    @Test("field build identity is recipe and exact-source bound without runtime hashing authority")
    func buildIdentityUsesStampedExactSourceAndProcedure() throws {
        let identity = try Self.repositoryFile("NembraApp/App/NembraCaptureBuildIdentity.swift")

        #expect(identity.contains("requiredFieldProcedureIdentifier = \"ES80-AUTHENTICATED-STATIONARY-v1\""))
        #expect(identity.contains("sourceCommitSHA.count == 40"))
        #expect(identity.contains("tuyaDependencyLockSHA256.count == 64"))
        #expect(identity.contains("procedureIdentifier == Self.requiredFieldProcedureIdentifier"))
        #expect(identity.contains("let expectedIdentifier = \"capture-v14-\\(sourceCommitSHA.prefix(12))\""))
        #expect(identity.contains("return buildIdentifier == expectedIdentifier"))
        #expect(!identity.contains("PassiveBluetoothCaptureRuntimeBuildIdentityReader"))
        #expect(!identity.contains("Task.detached"))
    }

    private static func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected current authenticated Capture source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private static func repositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
