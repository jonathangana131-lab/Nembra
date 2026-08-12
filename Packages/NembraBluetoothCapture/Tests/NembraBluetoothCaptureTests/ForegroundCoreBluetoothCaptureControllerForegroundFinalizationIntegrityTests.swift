import Foundation
import Testing

@Suite("Foreground CoreBluetooth finalization foreground integrity")
struct ForegroundCoreBluetoothCaptureControllerForegroundFinalizationIntegrityTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("foreground loss irreversibly invalidates the current durable capture before transport teardown")
    func foregroundLossPoisonsCurrentCaptureBeforeTransportTeardown() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "public func invalidateActiveCaptureForForegroundLoss()"))
        let end = try #require(source.range(
            of: "    /// Ends transport only after the caller has already frozen its immutable",
            range: start.upperBound..<source.endIndex
        ))
        let section = source[start.lowerBound..<end.lowerBound]

        let invalidation = try #require(section.range(of: "foregroundEvidenceIntegrityValid = false"))
        let teardown = try #require(section.range(of: "cancelActiveConnection(cause: .foregroundIntegrityLoss)"))

        #expect(section.distance(from: section.startIndex, to: invalidation.lowerBound)
            < section.distance(from: section.startIndex, to: teardown.lowerBound))
    }

    @Test("complete-target evidence cannot recover after foreground integrity is lost")
    func completeTargetEvidenceRequiresForegroundIntegrity() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "public var hasCompleteTargetEvidence: Bool"))
        let end = try #require(source.range(
            of: "    /// True only after the finite-acquisition Ready boundary itself has",
            range: start.upperBound..<source.endIndex
        ))
        let section = source[start.lowerBound..<end.lowerBound]

        #expect(section.contains("foregroundEvidenceIntegrityValid"))
    }

    @Test("foreground loss during the H recorder actor hop quarantines recorded H before queue commit")
    func recordedHorizonCannotCommitAfterForegroundLoss() throws {
        let source = try Self.controllerSource()
        let finalizer = try #require(source.range(of: "public func encodedFinalizedObservationHorizonJSON("))
        let recorderReturn = try #require(source.range(
            of: ".recordBoundaryWithMutationOutcome(on: recorder)",
            range: finalizer.lowerBound..<source.endIndex
        ))
        let queueCommit = try #require(source.range(
            of: "recordedHorizon.markBoundaryRecorded(",
            range: recorderReturn.upperBound..<source.endIndex
        ))
        let section = source[recorderReturn.upperBound..<queueCommit.lowerBound]

        #expect(section.contains("requireForegroundEvidenceIntegrity()"))
        #expect(source[recorderReturn.upperBound..<source.endIndex].contains("abortRecordedHorizonBeforeGateCommit"))
    }

    @Test("foreground loss during immutable JSON actor hop blocks terminal freeze")
    func committedHorizonCannotFreezeAfterForegroundLoss() throws {
        let source = try Self.controllerSource()
        let finalizer = try #require(source.range(of: "public func encodedFinalizedObservationHorizonJSON("))
        let artifactRead = try #require(source.range(
            of: "data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)",
            range: finalizer.lowerBound..<source.endIndex
        ))
        let freeze = try #require(source.range(
            of: "try committedHorizon.completeHorizonArtifactFreeze(",
            range: artifactRead.upperBound..<source.endIndex
        ))
        let section = source[artifactRead.upperBound..<freeze.lowerBound]

        #expect(section.contains("requireForegroundEvidenceIntegrity()"))
    }

    @Test("a genuinely fresh durable target session restores foreground integrity")
    func freshTargetSessionResetsForegroundIntegrity() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "private func beginTargetSessionIfNeeded(for identifier: UUID) throws"))
        let end = try #require(source.range(
            of: "    private func currentArtifactContext() throws",
            range: start.upperBound..<source.endIndex
        ))
        let section = source[start.lowerBound..<end.lowerBound]

        let reset = try #require(section.range(of: "foregroundEvidenceIntegrityValid = true"))
        let publishRecorder = try #require(section.range(of: "recorder = newRecorder"))

        #expect(section.distance(from: section.startIndex, to: reset.lowerBound)
            < section.distance(from: section.startIndex, to: publishRecorder.lowerBound))
    }
}
