import Foundation
import Testing

@Suite("Foreground controller Experiment One admission")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneAdmissionTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("Experiment One admission is consumed only by a non-public controller path")
    func admittedConnectIsPackageInternalAndOneShot() throws {
        let source = try Self.controllerSource()
        let signature = "func connect(\n        using admission: PassiveBluetoothExperimentOneCaptureAdmission,"
        let start = try #require(source.range(of: signature)?.lowerBound)
        let end = try #require(source.range(
            of: "\n    private func connectionCandidate(",
            range: start..<source.endIndex
        )?.lowerBound)
        let method = source[start..<end]

        #expect(!method.hasPrefix("public "))
        #expect(method.contains("let payload = try admission.consume()"))
        #expect(method.contains("payload.peripheralIdentifier"))
        #expect(method.contains("payload.powerCycleEvidence"))
        #expect(method.contains("beginExperimentOneTargetSession(using: payload)"))
        #expect(!method.contains("PassiveCoreBluetoothCaptureRecorder("))
    }

    @Test("admitted target must exist in the controller's current candidate epoch")
    func admittedTargetMustBeFreshlyDiscovered() throws {
        let source = try Self.controllerSource()
        let signature = "func connect(\n        using admission: PassiveBluetoothExperimentOneCaptureAdmission,"
        let start = try #require(source.range(of: signature)?.lowerBound)
        let end = try #require(source.range(
            of: "\n    private func connectionCandidate(",
            range: start..<source.endIndex
        )?.lowerBound)
        let method = source[start..<end]

        #expect(method.contains("connectionCandidate(for: payload.peripheralIdentifier"))
        #expect(source.contains("guard let peripheral = peripheralByIdentifier[peripheralIdentifier],"))
        #expect(source.contains("latestDiscoveryByIdentifier[peripheralIdentifier] != nil"))
        #expect(source.contains("clearCandidateCatalog()"))
    }

    @Test("controller retains sealed provenance while publishing the exact run-owned recorder")
    func admittedRecorderAndProvenanceStayJoined() throws {
        let source = try Self.controllerSource()
        #expect(source.contains("private struct ExperimentOneCaptureAuthority"))
        #expect(source.contains("private var experimentOneCaptureAuthority: ExperimentOneCaptureAuthority?"))

        let start = try #require(source.range(of: "private func beginExperimentOneTargetSession(")?.lowerBound)
        let end = try #require(source.range(
            of: "\n    private func publishTargetSession(",
            range: start..<source.endIndex
        )?.lowerBound)
        let method = source[start..<end]

        #expect(method.contains("payload.admissionIdentity"))
        #expect(method.contains("payload.powerCycleEvidence"))
        #expect(method.contains("payload.peripheralIdentifier"))
        #expect(method.contains("recorder: payload.recorder"))
        #expect(!method.contains("PassiveCoreBluetoothCaptureRecorder("))
    }

    @Test("generic research target publication cannot inherit Experiment One authority")
    func genericConnectClearsExperimentOneAuthority() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func beginTargetSessionIfNeeded(for identifier: UUID) throws")?.lowerBound)
        let end = try #require(source.range(
            of: "\n    private func beginExperimentOneTargetSession(",
            range: start..<source.endIndex
        )?.lowerBound)
        let method = source[start..<end]

        #expect(method.contains("experimentOneAuthority: nil"))
        #expect(!method.contains("admission.consume()"))
    }

    @Test("shared session publisher installs authority and recorder synchronously")
    func sessionPublisherKeepsRecorderAndAuthorityOneMutation() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func publishTargetSession(")?.lowerBound)
        let end = try #require(source.range(
            of: "\n    private func currentArtifactContext()",
            range: start..<source.endIndex
        )?.lowerBound)
        let method = source[start..<end]

        let authority = try #require(method.range(of: "experimentOneCaptureAuthority = experimentOneAuthority")?.lowerBound)
        let recorder = try #require(method.range(of: "self.recorder = newRecorder")?.lowerBound)
        #expect(authority < recorder)
        #expect(!method.contains("await "))
    }
}
