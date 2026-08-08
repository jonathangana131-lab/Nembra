import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Controller integration contract for zero-durable-H canonical rejection.
/// Software lifecycle truth only; no physical ES80 claim is established here.
struct ForegroundCoreBluetoothCaptureControllerUncommittedHorizonRecoveryTests {
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

    @Test("Horizon mutation uses zero-H outcome before recorded-H commit")
    func zeroHRejectionQuarantinesBeforeRecordedPath() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "            let horizonMutationOutcome = try await horizonAdmission")?.lowerBound)
        let end = try #require(source.range(of: "                data = try await recorder.encodedJSON", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let outcome = try #require(section.range(of: "recordBoundaryWithMutationOutcome")?.lowerBound)
        let rejection = try #require(section.range(of: "case let .rejectedBeforeMutation(rejection)")?.lowerBound)
        let quarantine = try #require(section.range(of: "abortUncommittedHorizon(after: rejection)")?.lowerBound)
        let recordedCommit = try #require(section.range(of: "recordedHorizon.markBoundaryRecorded")?.lowerBound)

        #expect(section.distance(from: section.startIndex, to: outcome) < section.distance(from: section.startIndex, to: rejection))
        #expect(section.distance(from: section.startIndex, to: rejection) < section.distance(from: section.startIndex, to: quarantine))
        #expect(section.distance(from: section.startIndex, to: quarantine) < section.distance(from: section.startIndex, to: recordedCommit))
        #expect(!section.contains("horizonAdmission.recordBoundary(on: recorder)"))
    }
}
