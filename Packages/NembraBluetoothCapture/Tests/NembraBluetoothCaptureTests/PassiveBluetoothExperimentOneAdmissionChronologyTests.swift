import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Software chronology contract for the sealed Experiment One controller handoff.
/// This is local monotonic callback ordering only, never BLE/RF emission timing or physical proof.
struct PassiveBluetoothExperimentOneAdmissionChronologyTests {
    private static func runSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveBluetoothExperimentOneRun.swift"),
            encoding: .utf8
        )
    }

    @Test("sealed admission payload carries producer-issued monotonic chronology")
    func payloadCarriesProducerIssuedUptime() throws {
        let source = try Self.runSource()
        let payload = try #require(source.range(of: "struct Payload {"))
        let payloadEnd = try #require(
            source.range(of: "private let payload: Payload", range: payload.upperBound..<source.endIndex)
        )
        let payloadBody = source[payload.lowerBound..<payloadEnd.lowerBound]

        #expect(payloadBody.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(payloadBody.contains("issuedAtUptimeNanoseconds: UInt64"))
        #expect(payloadBody.contains("self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds"))
    }

    @Test("issuance clock is captured after exact recorder construction and before handoff mint")
    func issuanceOrderingIsProducerOwned() throws {
        let source = try Self.runSource()
        let functionStart = try #require(source.range(of: "func issueCaptureAdmission("))
        let functionEnd = try #require(
            source.range(of: "fileprivate func beginCaptureRecorder(", range: functionStart.upperBound..<source.endIndex)
        )
        let body = source[functionStart.lowerBound..<functionEnd.lowerBound]

        let recorder = try #require(body.range(of: "let recorder = try beginCaptureRecorder(startedAt: startedAt)"))
        let clock = try #require(body.range(of: "let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds"))
        let admission = try #require(body.range(of: "return PassiveBluetoothExperimentOneCaptureAdmission("))

        #expect(recorder.lowerBound < clock.lowerBound)
        #expect(clock.lowerBound < admission.lowerBound)
    }
}
