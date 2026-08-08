import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground CoreBluetooth Experiment One foreground integrity")
struct ForegroundCoreBluetoothCaptureControllerExperimentOneForegroundIntegrityTests {
    private static func experimentOneConnectSection() throws -> Substring {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
        let start = try #require(
            source.range(of: "    func connectUsingExperimentOneAdmission(")?.lowerBound
        )
        let end = try #require(
            source.range(of: "    /// Cancels the active attempt", range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("run-owned recorder publication is the point that restores foreground integrity")
    func freshRecorderPublicationRestoresForegroundIntegrity() throws {
        let section = try Self.experimentOneConnectSection()
        let installRecorder = try #require(section.range(of: "recorder = payload.recorder")?.lowerBound)
        let restoreForeground = try #require(
            section.range(of: "foregroundEvidenceIntegrityValid = true", range: installRecorder..<section.endIndex)?.lowerBound
        )
        let beginAttempt = try #require(
            section.range(of: "targetState.beginAttempt(for: payload.peripheralIdentifier)", range: restoreForeground..<section.endIndex)?.lowerBound
        )

        #expect(installRecorder < restoreForeground)
        #expect(restoreForeground < beginAttempt)
        #expect(section.components(separatedBy: "foregroundEvidenceIntegrityValid = true").count - 1 == 1)
    }

    @Test("Experiment One bridge stays package-internal and performs no characteristic write")
    func bridgeRemainsPassiveAndPackageOwned() throws {
        let section = try Self.experimentOneConnectSection()
        #expect(!section.contains("public func connectUsingExperimentOneAdmission("))
        #expect(!section.contains("writeValue("))
    }
}
