import Foundation
import Testing

@Suite("ES80 Capture Simulator preflight snapshot retirement")
struct ES80CaptureSimulatorPreflightSnapshotHandoffTests {
    private static func captureSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("NembraApp")
                .appendingPathComponent("App")
                .appendingPathComponent("NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    @Test("authenticated Capture target carries no synthetic Simulator preflight authority")
    func authenticatedTargetRejectsSyntheticSnapshotAuthority() throws {
        let source = try Self.captureSource()

        #expect(source.contains("@main @MainActor\nstruct NembraCaptureApp: App"))
        #expect(source.contains("private let buildIdentity = NembraCaptureBuildIdentity.current"))
        #expect(!source.contains("PassiveBluetoothExperimentOneSimulatorQAFixture"))
        #expect(!source.contains("simulatorQASnapshot"))
        #expect(!source.contains("simulatorQAEvidenceLabel"))
        #expect(!source.contains("es80PassiveCaptureSimulatorQA"))
    }

    @Test("OFF1 admission remains exact-build and current-account gated rather than fixture gated")
    func off1AdmissionUsesRealFieldAuthority() throws {
        let source = try Self.captureSource()
        guard let startRange = source.range(of: "func startBaseline()"),
              let endRange = source.range(
                of: "private func beginCorrelationSeries",
                range: startRange.upperBound..<source.endIndex
              ) else {
            Issue.record("Could not isolate current OFF1 admission.")
            return
        }
        let start = String(source[startRange.lowerBound..<endRange.lowerBound])

        #expect(start.contains("guard buildIdentity.isAuthoritativeFieldBuild else"))
        #expect(start.contains("field_build_identity_unavailable"))
        #expect(start.contains("guard privateConfig, sdkAccountLoggedIn else"))
        #expect(start.contains("verifySDKMembership"))
        #expect(start.contains("TuyaSDKAccountIdentityLeaseGate.verdict"))
        #expect(start.contains("self.beginCorrelationSeries()"))
        #expect(!start.contains("#if DEBUG"))
        #expect(!start.contains("targetEnvironment(simulator)"))
    }

    @Test("accepted export handoff comes from the immutable accepted artifact, never a synthetic snapshot")
    func acceptedHandoffUsesSealedArtifactOnly() throws {
        let source = try Self.captureSource()

        #expect(source.contains("sealedAcceptedExport = self.makeExport("))
        #expect(source.contains("if phase == .accepted"))
        #expect(source.contains("guard let sealedAcceptedExport else"))
        #expect(source.contains("envelope = sealedAcceptedExport"))
        #expect(source.contains("Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable."))
        #expect(!source.contains("simulatorQASnapshot"))
    }
}
