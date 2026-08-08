import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red controller contract for the third partial-H class.
///
/// Once H is durable and queue-committed, a failure while materializing,
/// validating, or freezing the immutable artifact must quarantine that exact
/// producer-issued committed H. The controller may not strand the gate in
/// `.horizonBoundaryRecorded`, retry under newer authority, or pretend a
/// terminal artifact exists.
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

    @Test("committed H pre-freeze failure consumes exact quarantine authority")
    func finalizerQuarantinesCommittedHBeforeFreezeFailureEscapes() throws {
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

        let commit = try #require(
            section.range(of: "committedHorizon = try recordedHorizon.markBoundaryRecorded(")?.lowerBound
        )
        let materialize = try #require(
            section.range(of: "recorder.encodedJSON(", range: commit..<section.endIndex)?.lowerBound
        )
        let quarantine = try #require(
            section.range(
                of: "abortCommittedHorizonBeforeArtifactFreeze(committedHorizon)",
                range: commit..<section.endIndex
            )?.lowerBound
        )

        #expect(section.distance(from: section.startIndex, to: commit)
            < section.distance(from: section.startIndex, to: materialize))
        #expect(section.distance(from: section.startIndex, to: materialize)
            < section.distance(from: section.startIndex, to: quarantine))

        // The exact producer-issued committed H must be the recovery input.
        #expect(section[quarantine...].contains("committedHorizon"))
        #expect(!section[commit..<quarantine].contains("beginHorizon("))
    }
}
