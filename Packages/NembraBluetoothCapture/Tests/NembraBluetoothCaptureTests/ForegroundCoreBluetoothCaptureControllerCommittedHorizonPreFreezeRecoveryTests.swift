import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Locks the live controller to the package-owned committed-H pre-freeze
/// quarantine. A durable + queue-committed Horizon must never be left in
/// `.horizonBoundaryRecorded` when artifact materialization/authority/freeze
/// fails before terminalization.
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

    @Test("committed Horizon failures quarantine before generic capture failure")
    func committedHorizonFailureConsumesExactPreFreezeAbort() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    private func beginTargetSessionIfNeeded",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let section = source[start..<end]

        let committed = try #require(
            section.range(of: "committedHorizon = try recordedHorizon.markBoundaryRecorded(")?.lowerBound
        )
        let encoded = try #require(
            section.range(of: "let data = try await recorder.encodedJSON(", range: committed..<section.endIndex)?.lowerBound
        )
        let abort = try #require(
            section.range(
                of: "abortCommittedHorizonBeforeArtifactFreeze(\n                    committedHorizon\n                )",
                range: encoded..<section.endIndex
            )?.lowerBound
        )
        let freeze = try #require(
            section.range(
                of: "committedHorizon.completeHorizonArtifactFreeze(",
                range: encoded..<section.endIndex
            )?.lowerBound
        )
        let genericFailure = try #require(
            section.range(of: "failCapture(error)", range: abort..<section.endIndex)?.lowerBound
        )

        #expect(section.distance(from: section.startIndex, to: committed)
            < section.distance(from: section.startIndex, to: encoded))
        #expect(section.distance(from: section.startIndex, to: encoded)
            < section.distance(from: section.startIndex, to: abort))
        #expect(section.distance(from: section.startIndex, to: abort)
            < section.distance(from: section.startIndex, to: genericFailure))
        #expect(section.distance(from: section.startIndex, to: freeze)
            < section.distance(from: section.startIndex, to: genericFailure))
    }
}
