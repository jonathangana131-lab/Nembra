import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Product contract for the producer-owned Experiment One admission handoff clock.
/// This is software monotonic chronology only, never BLE/RF emission time or physical ES80 proof.
struct PassiveBluetoothExperimentOneAdmissionHandoffUptimeTests {
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

    @Test("admission payload carries producer-sampled monotonic issuance boundary")
    func payloadCarriesProducerSampledBoundary() throws {
        let source = try Self.runSource()
        let issueStart = try #require(source.range(of: "func issueCaptureAdmission("))
        let beginRecorder = try #require(
            source.range(
                of: "let recorder = try beginCaptureRecorder(startedAt: startedAt)",
                range: issueStart.upperBound..<source.endIndex
            )
        )
        let sample = try #require(
            source.range(
                of: "let issuedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds",
                range: beginRecorder.upperBound..<source.endIndex
            )
        )
        let admission = try #require(
            source.range(
                of: "return PassiveBluetoothExperimentOneCaptureAdmission(",
                range: sample.upperBound..<source.endIndex
            )
        )
        let payloadField = try #require(source.range(of: "let issuedAtUptimeNanoseconds: UInt64"))

        #expect(beginRecorder.lowerBound < sample.lowerBound)
        #expect(sample.lowerBound < admission.lowerBound)
        #expect(payloadField.lowerBound < issueStart.lowerBound)
    }

    @Test("monotonic handoff boundary cannot be supplied by the caller")
    func callerCannotSupplyBoundary() throws {
        let source = try Self.runSource()
        let issueStart = try #require(source.range(of: "func issueCaptureAdmission("))
        let issueEnd = try #require(
            source.range(
                of: "fileprivate func beginCaptureRecorder(",
                range: issueStart.upperBound..<source.endIndex
            )
        )
        let signature = source[issueStart.lowerBound..<issueEnd.lowerBound]

        #expect(!signature.contains("issuedAtUptimeNanoseconds:"))
        #expect(signature.contains("DispatchTime.now().uptimeNanoseconds"))
    }
}
