import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth pre-attempt Ready abandonment")
struct ForegroundCoreBluetoothCaptureControllerPreAttemptReadyAbandonmentTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("allocated Ready is quarantined before its first recorder attempt")
    func preRecorderFailureConsumesUnusedReadyAdmission() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func requireForegroundEvidenceIntegrity", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let begin = try #require(section.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(")?.lowerBound)
        let flush = try #require(section.range(of: "await self.flushPendingEvents(through: admission.queueCutoff)", range: begin..<section.endIndex)?.lowerBound)
        let preservedFailure = try #require(section.range(of: "let preAttemptFailure = error", range: flush..<section.endIndex)?.lowerBound)
        let abandonment = try #require(section.range(of: "let abandonment = try admission.abandonBeforeRecorderMutation()", range: preservedFailure..<section.endIndex)?.lowerBound)
        let quarantine = try #require(section.range(of: "abortUncommittedReady(", range: abandonment..<section.endIndex)?.lowerBound)
        let firstRecorder = try #require(section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)", range: quarantine..<section.endIndex)?.lowerBound)
        #expect(begin < flush)
        #expect(flush < preservedFailure)
        #expect(preservedFailure < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < firstRecorder)
        let preAttempt = section[begin..<firstRecorder]
        #expect(preAttempt.contains("requireForegroundEvidenceIntegrity()"))
        #expect(preAttempt.contains("validateBoundaryAuthority(admission.authority)"))
        #expect(!preAttempt.contains("try? admission.abandonBeforeRecorderMutation()"))
        #expect(!preAttempt.contains("try? self.observationBoundaryQueueGate.abortUncommittedReady"))
    }

    @Test("pre-attempt Ready abandonment remains distinct from mutation-point rejection")
    func preservesDistinctZeroMutationReadyAuthorities() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound)
        let end = try #require(source.range(of: "\n    private func requireForegroundEvidenceIntegrity", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        #expect(section.components(separatedBy: "admission.abandonBeforeRecorderMutation()").count - 1 == 1)
        #expect(section.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(section.contains("abortUncommittedReady(after: rejection)"))
        #expect(section.contains("abortUncommittedReady("))
    }
}
