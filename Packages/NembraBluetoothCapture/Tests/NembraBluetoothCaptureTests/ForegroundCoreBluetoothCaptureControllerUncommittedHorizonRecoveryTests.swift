import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerUncommittedHorizonRecoveryTests {
    private static func controllerSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"), encoding: .utf8)
    }

    @Test("Horizon mutation uses zero-H outcome before recorded-H commit")
    func zeroHRejectionQuarantinesBeforeRecordedPath() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let horizonMutationOutcome = try await horizonAdmission")?.lowerBound)
        let end = try #require(source.range(of: "            let data: Data", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        let outcome = try #require(section.range(of: "recordBoundaryWithMutationOutcome")?.lowerBound)
        let rejection = try #require(section.range(of: "case let .rejectedBeforeMutation(rejection)")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortUncommittedHorizon(after: rejection)")?.lowerBound)
        let recordedCommit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)
        #expect(outcome < rejection)
        #expect(rejection < quarantine)
        #expect(quarantine < recordedCommit)
        #expect(!section.contains("horizonAdmission.recordBoundary(on: recorder)"))
    }
}
