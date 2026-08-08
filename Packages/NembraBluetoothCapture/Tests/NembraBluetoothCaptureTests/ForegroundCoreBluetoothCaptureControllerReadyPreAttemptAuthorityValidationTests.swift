import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth Ready pre-attempt authority")
struct ForegroundCoreBluetoothCaptureControllerReadyPreAttemptAuthorityValidationTests {
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

    @Test("Ready revalidates foreground, health, and exact admission authority before recorder attempt")
    func validatesExactAuthorityBeforeFirstRecorderAttempt() throws {
        let source = try Self.controllerSource()
        let functionStart = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound
        )
        let functionEnd = try #require(
            source.range(
                of: "    private func requireForegroundEvidenceIntegrity()",
                range: functionStart..<source.endIndex
            )?.lowerBound
        )
        let section = source[functionStart..<functionEnd]

        let begin = try #require(
            section.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(")?.lowerBound
        )
        let drain = try #require(
            section.range(
                of: "await self.flushPendingEvents(through: admission.queueCutoff)",
                range: begin..<section.endIndex
            )?.lowerBound
        )
        let foreground = try #require(
            section.range(
                of: "try self.requireForegroundEvidenceIntegrity()",
                range: drain..<section.endIndex
            )?.lowerBound
        )
        let health = try #require(
            section.range(
                of: "try self.ensureCaptureHealthy()",
                range: foreground..<section.endIndex
            )?.lowerBound
        )
        let authority = try #require(
            section.range(
                of: "try self.validateBoundaryAuthority(admission.authority)",
                range: health..<section.endIndex
            )?.lowerBound
        )
        let preservedFailure = try #require(
            section.range(
                of: "let preAttemptFailure = error",
                range: authority..<section.endIndex
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
        let recorderAttempt = try #require(
            section.range(
                of: ".recordBoundaryWithMutationOutcome(on: recorder)",
                range: quarantine..<section.endIndex
            )?.lowerBound
        )

        #expect(begin < drain)
        #expect(drain < foreground)
        #expect(foreground < health)
        #expect(health < authority)
        #expect(authority < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < recorderAttempt)
        #expect(section[authority..<recorderAttempt].contains("throw preAttemptFailure"))
        #expect(!section[begin..<recorderAttempt].contains("try? admission.abandonBeforeRecorderMutation()"))
        #expect(!section[begin..<recorderAttempt].contains("try? self.observationBoundaryQueueGate.abortUncommittedReady(after: abandonment)"))
    }

    @Test("Ready pre-attempt abandonment stays distinct from canonical mutation-point rejection")
    func keepsDistinctZeroMutationAuthorities() throws {
        let source = try Self.controllerSource()
        let functionStart = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded()")?.lowerBound
        )
        let functionEnd = try #require(
            source.range(
                of: "    private func requireForegroundEvidenceIntegrity()",
                range: functionStart..<source.endIndex
            )?.lowerBound
        )
        let section = source[functionStart..<functionEnd]

        #expect(section.components(separatedBy: "abandonBeforeRecorderMutation()").count - 1 == 1)
        #expect(section.contains("case let .rejectedBeforeMutation(rejection):"))
        #expect(section.contains("abortUncommittedReady(after: abandonment)"))
        #expect(section.contains("abortUncommittedReady(after: rejection)"))
    }
}
