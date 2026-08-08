import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Software monotonic ordering only; no BLE/RF emission time or physical ES80 claim.
struct ForegroundCoreBluetoothCaptureControllerExperimentOnePostAdmissionRediscoveryTests {
    private static func source(named filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources").appendingPathComponent("NembraBluetoothCapture").appendingPathComponent(filename), encoding: .utf8)
    }

    private static func consumerBody(_ source: String) throws -> Substring {
        let start = try #require(source.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(source.range(of: "public func cancelActiveConnection()", range: start.upperBound..<source.endIndex))
        return source[start.lowerBound..<end.lowerBound]
    }

    @Test("sealed admission carries a producer-issued monotonic handoff boundary")
    func admissionCarriesIssuedUptime() throws {
        let source = try Self.source(named: "PassiveBluetoothExperimentOneRun.swift")
        #expect(source.contains("issuedAtUptimeNanoseconds"))
        #expect(source.contains("DispatchTime.now().uptimeNanoseconds"))
    }

    @Test("controller requires strictly post-admission rediscovery before admission consumption and recorder installation")
    func currentCatalogMustBePostAdmissionEvidence() throws {
        let body = try Self.consumerBody(try Self.source(named: "ForegroundCoreBluetoothCaptureController.swift"))
        let preview = try #require(body.range(of: "let preview = try admission.previewForControllerStaging()"))
        let latestAdvertisement = try #require(body.range(of: "latestAdvertisementByIdentifier[preview.peripheralIdentifier]"))
        let freshness = try #require(body.range(of: "receivedAtUptimeNanoseconds > preview.issuedAtUptimeNanoseconds"))
        let consume = try #require(body.range(of: "let payload = try admission.consume()"))
        let selectTarget = try #require(body.range(of: "targetState.selectTarget(payload.peripheralIdentifier)"))
        let installRecorder = try #require(body.range(of: "recorder = payload.recorder"))
        #expect(preview.lowerBound < latestAdvertisement.lowerBound)
        #expect(latestAdvertisement.lowerBound < freshness.lowerBound)
        #expect(freshness.lowerBound < consume.lowerBound)
        #expect(consume.lowerBound < selectTarget.lowerBound)
        #expect(consume.lowerBound < installRecorder.lowerBound)
    }
}
