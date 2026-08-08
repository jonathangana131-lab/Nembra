import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture Ready recovery diagnostic")
struct ForegroundCoreBluetoothCaptureControllerReadyRecoveryDiagnosticTests {
    private static func packageSource(_ filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func controllerSection(
        from startMarker: String,
        through endMarker: String
    ) throws -> Substring {
        let source = try packageSource("ForegroundCoreBluetoothCaptureController.swift")
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("Ready admission owns a one-shot pre-recorder abandonment capability")
    func readyAdmissionCanProveRecorderWasNeverAttempted() throws {
        let decisionSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryTransactionDecision.swift"
        )

        #expect(decisionSource.contains("ReadyRecorderMutationAbandonmentReceipt"))
        #expect(
            decisionSource.contains(
                "func abandonBeforeRecorderMutation() throws -> ReadyRecorderMutationAbandonmentReceipt"
            )
        )
    }

    @Test("Ready gate distinguishes deliberate pre-attempt abandonment from mutation-point rejection")
    func readyGateHasDistinctAbandonmentOrigin() throws {
        let gateSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryQueueGate.swift"
        )

        #expect(gateSource.contains("uncommittedReadyAbandonedBeforeRecorderMutation"))
        #expect(
            gateSource.contains(
                "after abandonment: PassiveCoreBluetoothObservationBoundaryTransactionDecision.ReadyRecorderMutationAbandonmentReceipt"
            )
        )
        #expect(gateSource.contains("abortUncommittedReady("))
    }

    @Test("controller consumes Ready abandonment before its first recorder attempt")
    func controllerQuarantinesAllocatedReadyBeforeRecorderAttempt() throws {
        let section = try Self.controllerSection(
            from: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()",
            through: "    private func validateBoundaryAuthority("
        )

        let begin = try #require(
            section.range(of: "PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(")?.lowerBound
        )
        let flush = try #require(
            section.range(
                of: "await self.flushPendingEvents(through: admission.queueCutoff)",
                range: begin..<section.endIndex
            )?.lowerBound
        )
        let abandonment = try #require(
            section.range(
                of: "admission.abandonBeforeRecorderMutation()",
                range: flush..<section.endIndex
            )?.lowerBound
        )
        let quarantine = try #require(
            section.range(
                of: "abortUncommittedReady(after: abandonment)",
                range: abandonment..<section.endIndex
            )?.lowerBound
        )
        let firstRecorderAttempt = try #require(
            section.range(
                of: "admission.recordBoundaryWithMutationOutcome(on: recorder)",
                range: quarantine..<section.endIndex
            )?.lowerBound
        )

        #expect(begin < flush)
        #expect(flush < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < firstRecorderAttempt)
    }

    @Test("durable Ready and Horizon recovery authority is never try-question-mark suppressed")
    func recordedBoundaryRecoveryFailureMustWin() throws {
        let readySection = try Self.controllerSection(
            from: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()",
            through: "    private func validateBoundaryAuthority("
        )
        let horizonSection = try Self.controllerSection(
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            through: "    private func beginTargetSessionIfNeeded"
        )

        #expect(
            !readySection.contains(
                "try? self.observationBoundaryQueueGate.abortRecordedReadyBeforeGateCommit"
            )
        )
        #expect(
            !horizonSection.contains(
                "try? observationBoundaryQueueGate.abortRecordedHorizonBeforeGateCommit"
            )
        )
    }
}
