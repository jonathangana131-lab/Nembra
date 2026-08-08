import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red current-spine provenance contract for the Experiment One handoff.
///
/// This intentionally adds no product implementation. It prevents the current terminal-recovery
/// flagship from later accepting a stale controller catalog entry as if it were a fresh
/// post-admission rediscovery. The uptime comparison is software callback chronology only; it is
/// not BLE/RF emission time and establishes no physical ES80 identity or protocol semantics.
struct ForegroundCoreBluetoothCaptureControllerExperimentOneCurrentSpineRediscoveryTests {
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

    @Test("current flagship must consume the sealed Experiment One admission in the controller")
    func currentFlagshipOwnsSealedAdmissionConsumer() throws {
        let body = try Self.consumerBody(try Self.controllerSource())
        #expect(body.contains("admission.consume()"))
        #expect(body.contains("recorder = payload.recorder"))
        #expect(!body.contains("beginTargetSessionIfNeeded(for:"))
    }

    @Test("sealed admission carries a producer-issued monotonic handoff boundary")
    func admissionCarriesIssuedUptime() throws {
        let source = try Self.runSource()
        #expect(source.contains("issuedAtUptimeNanoseconds"))
        #expect(source.contains("DispatchTime.now().uptimeNanoseconds"))
    }

    @Test("controller requires rediscovery after admission before selecting target or installing recorder")
    func currentCatalogMustBePostAdmissionEvidence() throws {
        let body = try Self.consumerBody(try Self.controllerSource())
        let latestAdvertisement = try #require(
            body.range(of: "latestAdvertisementByIdentifier[payload.peripheralIdentifier]")
        )
        let freshness = try #require(
            body.range(of: "receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds")
        )
        let selectTarget = try #require(
            body.range(of: "targetState.selectTarget(payload.peripheralIdentifier)")
        )
        let installRecorder = try #require(body.range(of: "recorder = payload.recorder"))

        #expect(latestAdvertisement.lowerBound < freshness.lowerBound)
        #expect(freshness.lowerBound < selectTarget.lowerBound)
        #expect(freshness.lowerBound < installRecorder.lowerBound)
    }
}
