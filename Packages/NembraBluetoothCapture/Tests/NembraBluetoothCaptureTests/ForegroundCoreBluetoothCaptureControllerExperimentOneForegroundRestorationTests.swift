import Foundation
import Testing

@Suite("Experiment One fresh-session foreground integrity")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneForegroundRestorationTests {
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

    @Test("sealed Experiment One recorder publication restores foreground integrity")
    func freshRunOwnedRecorderRestoresForegroundEvidenceValidity() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(of: "    func connectUsingExperimentOneAdmission(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    /// Cancels the active attempt",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let method = source[start..<end]

        let sessionBegin = try #require(method.range(of: "acquisitionLedger.beginTargetSession()"))
        let restore = try #require(
            method.range(
                of: "foregroundEvidenceIntegrityValid = true",
                range: sessionBegin.upperBound..<method.endIndex
            )
        )
        let recorderInstall = try #require(
            method.range(
                of: "recorder = payload.recorder",
                range: restore.upperBound..<method.endIndex
            )
        )
        let attempt = try #require(
            method.range(
                of: "targetState.beginAttempt(for: payload.peripheralIdentifier)",
                range: recorderInstall.upperBound..<method.endIndex
            )
        )

        #expect(sessionBegin.lowerBound < restore.lowerBound)
        #expect(restore.lowerBound < recorderInstall.lowerBound)
        #expect(recorderInstall.lowerBound < attempt.lowerBound)
    }
}
