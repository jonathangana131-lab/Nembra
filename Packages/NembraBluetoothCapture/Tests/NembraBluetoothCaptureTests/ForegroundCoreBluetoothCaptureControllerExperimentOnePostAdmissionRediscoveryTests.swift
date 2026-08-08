import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Software monotonic provenance contract for the Experiment One handoff.
/// This proves callback chronology only; it does not claim BLE/RF emission time or physical ES80 identity.
struct ForegroundCoreBluetoothCaptureControllerExperimentOnePostAdmissionRediscoveryTests {
    private static func source(named filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent(filename),
            encoding: .utf8
        )
    }

    private static func controllerSource() throws -> String {
        try source(named: "ForegroundCoreBluetoothCaptureController.swift")
    }

    private static func runSource() throws -> String {
        try source(named: "PassiveBluetoothExperimentOneRun.swift")
    }

    private static func consumerBody(_ source: String) throws -> Substring {
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(
            source.range(
                of: "public func cancelActiveConnection()",
                range: start.upperBound..<source.endIndex
            )
        )
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("sealed admission carries the producer-issued monotonic handoff boundary")
    func admissionCarriesIssuedUptime() throws {
        let source = try Self.runSource()
        #expect(source.contains("issuedAtUptimeNanoseconds"))
        #expect(source.contains("DispatchTime.now().uptimeNanoseconds"))
    }

    @Test("controller requires strictly post-admission rediscovery before installing its recorder")
    func currentCatalogMustBePostAdmissionEvidence() throws {
        let body = try Self.consumerBody(try Self.controllerSource())
        let latestAdvertisement = try #require(
            body.range(of: "latestAdvertisementByIdentifier[payload.peripheralIdentifier]")
        )
        let freshness = try #require(
            body.range(of: "receivedAtUptimeNanoseconds > payload.issuedAtUptimeNanoseconds")
        )
        let selectTarget = try #require(
            body.range(of: "targetState.selectTarget(payload.peripheralIdentifier)")
        )
        let installRecorder = try #require(body.range(of: "recorder = payload.recorder"))

        #expect(latestAdvertisement.lowerBound < freshness.lowerBound)
        #expect(freshness.lowerBound < selectTarget.lowerBound)
        #expect(freshness.lowerBound < installRecorder.lowerBound)
    }

    @Test("stale catalog evidence fails with a dedicated rediscovery error before recorder publication")
    func staleCatalogHasExplicitFailure() throws {
        let body = try Self.consumerBody(try Self.controllerSource())
        let error = try #require(
            body.range(of: "experimentOnePostAdmissionRediscoveryRequired(payload.peripheralIdentifier)")
        )
        let installRecorder = try #require(body.range(of: "recorder = payload.recorder"))
        #expect(error.lowerBound < installRecorder.lowerBound)
    }
}
