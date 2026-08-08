import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerRecordedHorizonRecoveryTests {
    private static func controllerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"), encoding: .utf8)
    }

    @Test("durable Horizon commit failure quarantines exact recorded H before generic failure")
    func recordedHorizonCommitFailureUsesProducerQuarantine() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let horizonMutationOutcome = try await horizonAdmission")?.lowerBound)
        let end = try #require(source.range(of: "            let data: Data", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let record = try #require(section.range(of: "recordBoundaryWithMutationOutcome(on: recorder)")?.lowerBound)
        let recorded = try #require(section.range(of: "case let .recorded(boundary)")?.lowerBound)
        let commit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortRecordedHorizonBeforeGateCommit")?.lowerBound)
        #expect(record < recorded)
        #expect(recorded < commit)
        #expect(commit < quarantine)
        #expect(!section[commit..<quarantine].contains("await"))
    }
}
