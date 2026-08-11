import Foundation
import Testing

@Suite("Foreground CoreBluetooth Ready pre-attempt authority validation")
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

    @Test("Ready authority drift after FIFO drain is abandoned before recorder attempt")
    func readyRevalidatesExactAuthorityBeforeFirstRecorderAttempt() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(of: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded() {")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    private func validateBoundaryAuthority(",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let section = source[start..<end]

        let admission = try #require(
            section.range(of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(")
        )
        let flush = try #require(
            section.range(
                of: "await self.flushPendingEvents(through: admission.queueCutoff)",
                range: admission.upperBound..<section.endIndex
            )
        )
        let authorityCheck = try #require(
            section.range(
                of: "try self.validateBoundaryAuthority(admission.authority)",
                range: flush.upperBound..<section.endIndex
            )
        )
        let abandonment = try #require(
            section.range(
                of: "admission.abandonBeforeRecorderAttempt()",
                range: authorityCheck.upperBound..<section.endIndex
            )
        )
        let recorderAttempt = try #require(
            section.range(
                of: "admission.recordBoundaryWithMutationOutcome(on: recorder)",
                range: abandonment.upperBound..<section.endIndex
            )
        )

        #expect(flush.lowerBound < authorityCheck.lowerBound)
        #expect(authorityCheck.lowerBound < abandonment.lowerBound)
        #expect(abandonment.lowerBound < recorderAttempt.lowerBound)
    }
}
