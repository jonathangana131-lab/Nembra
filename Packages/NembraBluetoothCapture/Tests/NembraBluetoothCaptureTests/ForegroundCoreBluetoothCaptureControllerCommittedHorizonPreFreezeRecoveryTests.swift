import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Controller integration contract for durable + queue-committed Horizon failure
/// before terminal artifact freeze. Software lifecycle truth only.
struct ForegroundCoreBluetoothCaptureControllerCommittedHorizonPreFreezeRecoveryTests {
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

    @Test("committed H is quarantined if artifact read or freeze cannot complete")
    func committedHorizonFailureUsesExactPreFreezeQuarantine() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary")?.lowerBound)
        let end = try #require(source.range(of: "            lastFinalizedArtifactAuthority = committedHorizon.authority", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let commit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)
        let artifactRead = try #require(section.range(of: "recorder.encodedJSON")?.lowerBound)
        let freeze = try #require(section.range(of: "committedHorizon.completeHorizonArtifactFreeze")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortCommittedHorizonBeforeArtifactFreeze(\n                        committedHorizon")?.lowerBound)

        #expect(section.distance(from: section.startIndex, to: commit) < section.distance(from: section.startIndex, to: artifactRead))
        #expect(section.distance(from: section.startIndex, to: artifactRead) < section.distance(from: section.startIndex, to: freeze))
        #expect(section.distance(from: section.startIndex, to: freeze) < section.distance(from: section.startIndex, to: quarantine))
        #expect(section.contains("try validateBoundaryAuthority(committedHorizon.authority)"))
    }

    @Test("terminal queue resolution remains success-only after freeze")
    func resolutionOccursOnlyAfterSuccessfulFreeze() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let committedHorizon: PassiveCoreBluetoothObservationBoundaryTransactionDecision.CommittedHorizonBoundary")?.lowerBound)
        let end = try #require(source.range(of: "            return data", range: start..<source.endIndex)?.upperBound)
        let section = source[start..<end]

        let freeze = try #require(section.range(of: "committedHorizon.completeHorizonArtifactFreeze")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortCommittedHorizonBeforeArtifactFreeze")?.lowerBound)
        let finalizedAuthority = try #require(section.range(of: "lastFinalizedArtifactAuthority = committedHorizon.authority")?.lowerBound)
        let resolution = try #require(section.range(of: "resolveQueuedEvidenceAfterTerminalHorizon()")?.lowerBound)

        #expect(section.distance(from: section.startIndex, to: freeze) < section.distance(from: section.startIndex, to: quarantine))
        #expect(section.distance(from: section.startIndex, to: quarantine) < section.distance(from: section.startIndex, to: finalizedAuthority))
        #expect(section.distance(from: section.startIndex, to: finalizedAuthority) < section.distance(from: section.startIndex, to: resolution))
        #expect(!section.contains("retireQueuedEvidenceAfterTerminalHorizon()"))
    }
}
