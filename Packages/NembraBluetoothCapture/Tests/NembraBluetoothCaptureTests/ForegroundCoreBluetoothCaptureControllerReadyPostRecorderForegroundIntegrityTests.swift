import Foundation
import Testing

@Suite("Foreground CoreBluetooth Ready post-recorder foreground integrity")
struct ForegroundCoreBluetoothCaptureControllerReadyPostRecorderForegroundIntegrityTests {
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

    @Test("foreground loss during Ready recorder actor hop is rechecked before typed queue commit")
    func recordedReadyCannotCommitAfterForegroundLoss() throws {
        let source = try Self.controllerSource()
        let readyFunction = try #require(source.range(of: "private func beginFiniteAcquisitionReadyBoundaryIfNeeded()"))
        let recorderReturn = try #require(source.range(
            of: "let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)",
            range: readyFunction.lowerBound..<source.endIndex
        ))
        let queueCommit = try #require(source.range(
            of: "recordedReady.markBoundaryRecorded(",
            range: recorderReturn.upperBound..<source.endIndex
        ))
        let section = source[recorderReturn.upperBound..<queueCommit.lowerBound]
        #expect(section.contains("requireForegroundEvidenceIntegrity()"))
    }

    @Test("post-recorder Ready failure quarantines exact durable Ready without suppressing recovery failure")
    func recordedReadyPostRecorderFailureUsesExplicitRecoveryPrecedence() throws {
        let source = try Self.controllerSource()
        let readyFunction = try #require(source.range(of: "private func beginFiniteAcquisitionReadyBoundaryIfNeeded()"))
        let recorderReturn = try #require(source.range(
            of: "let outcome = try await admission.recordBoundaryWithMutationOutcome(on: recorder)",
            range: readyFunction.lowerBound..<source.endIndex
        ))
        let functionEnd = try #require(source.range(
            of: "    private func requireForegroundEvidenceIntegrity() throws",
            range: recorderReturn.upperBound..<source.endIndex
        ))
        let section = source[recorderReturn.upperBound..<functionEnd.lowerBound]
        #expect(section.contains("abortRecordedReadyBeforeGateCommit"))
        #expect(!section.contains("try? self.observationBoundaryQueueGate.abortRecordedReadyBeforeGateCommit"))
    }
}
