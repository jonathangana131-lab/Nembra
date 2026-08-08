import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth pre-attempt Ready abandonment")
struct ForegroundCoreBluetoothCaptureControllerPreAttemptReadyAbandonmentTests {
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

    private static func readySection() throws -> Substring {
        let source = try controllerSource()
        let functionStart = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound
        )
        let functionEnd = try #require(
            source.range(
                of: "    private func validateBoundaryAuthority(",
                range: functionStart..<source.endIndex
            )?.lowerBound
        )
        return source[functionStart..<functionEnd]
    }

    @Test("allocated Ready is exactly quarantined before the first recorder attempt")
    func preRecorderFailureConsumesUnusedAdmissionBeforeRecorderAttempt() throws {
        let section = try Self.readySection()
        let begin = try #require(
            section.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(")?.lowerBound
        )
        let flush = try #require(
            section.range(
                of: "await self.flushPendingEvents(through: admission.queueCutoff)",
                range: begin..<section.endIndex
            )?.lowerBound
        )
        let preservedFailure = try #require(
            section.range(
                of: "let preAttemptFailure = error",
                range: flush..<section.endIndex
            )?.lowerBound
        )
        let abandonment = try #require(
            section.range(
                of: "let abandonment = try admission.abandonBeforeRecorderMutation()",
                range: preservedFailure..<section.endIndex
            )?.lowerBound
        )
        let quarantine = try #require(
            section.range(
                of: "try self.observationBoundaryQueueGate.abortUncommittedReady(after: abandonment)",
                range: abandonment..<section.endIndex
            )?.lowerBound
        )
        let firstRecorderAttempt = try #require(
            section.range(
                of: ".recordBoundaryWithMutationOutcome(on: recorder)",
                range: quarantine..<section.endIndex
            )?.lowerBound
        )

        #expect(begin < flush)
        #expect(flush < preservedFailure)
        #expect(preservedFailure < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < firstRecorderAttempt)

        let preAttemptSection = section[begin..<firstRecorderAttempt]
        #expect(!preAttemptSection.contains("try? admission.abandonBeforeRecorderMutation()"))
        #expect(!preAttemptSection.contains("try? self.observationBoundaryQueueGate.abortUncommittedReady(after: abandonment)"))
    }

    @Test("pre-attempt Ready abandonment stays distinct from mutation-point rejection")
    func preservesDistinctZeroMutationAuthorities() throws {
        let section = try Self.readySection()

        #expect(section.components(separatedBy: "abandonBeforeRecorderMutation()").count - 1 == 1)
        #expect(section.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(section.contains("abortUncommittedReady(after: rejection)"))
        #expect(section.contains("abortUncommittedReady(after: abandonment)"))
    }
}
