import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerPreAttemptHorizonAbandonmentTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/NembraBluetoothCapture/ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("failure after H allocation but before recorder attempt consumes pre-attempt abandonment")
    func preRecorderFailureHasExactQuarantineConsumer() throws {
        let source = try Self.controllerSource()
        let functionStart = try #require(source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound)
        let functionEnd = try #require(source.range(of: "    private func beginTargetSessionIfNeeded", range: functionStart..<source.endIndex)?.lowerBound)
        let section = source[functionStart..<functionEnd]

        let begin = try #require(section.range(of: "let horizonAdmission = try durationPermit.beginHorizon(")?.lowerBound)
        let firstRecorderAttempt = try #require(section.range(of: ".recordBoundaryWithMutationOutcome(on: recorder)", range: begin..<section.endIndex)?.lowerBound)
        let abandonment = try #require(section.range(of: "horizonAdmission.abandonBeforeRecorderMutation()", range: begin..<firstRecorderAttempt)?.lowerBound)
        let quarantine = try #require(section.range(of: "abortUncommittedHorizon(after: abandonment)", range: abandonment..<firstRecorderAttempt)?.lowerBound)

        #expect(begin < abandonment)
        #expect(abandonment < quarantine)
        #expect(quarantine < firstRecorderAttempt)
        #expect(!section[begin..<firstRecorderAttempt].contains("try? observationBoundaryQueueGate.abortUncommittedHorizon(after: abandonment)"))
    }
}
