import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Controller integration contract for producer-issued recorded-H quarantine.
/// This is software lifecycle truth only; it establishes no physical ES80 evidence.
struct ForegroundCoreBluetoothCaptureControllerRecordedHorizonRecoveryTests {
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

    @Test("durable Horizon commit failure quarantines exact recorded H before generic failure")
    func recordedHorizonCommitFailureUsesProducerQuarantine() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let horizonMutationOutcome = try await horizonAdmission")?.lowerBound)
        let end = try #require(source.range(of: "            let data: Data", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let record = try #require(section.range(of: "recordBoundaryWithMutationOutcome")?.lowerBound)
        let recorded = try #require(section.range(of: "case let .recorded(recordedHorizon)")?.lowerBound)
        let commit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortRecordedHorizonBeforeGateCommit")?.lowerBound)
        #expect(record < recorded)
        #expect(recorded < commit)
        #expect(commit < quarantine)
        #expect(section[commit..<quarantine].range(of: "await") == nil)
    }
}
