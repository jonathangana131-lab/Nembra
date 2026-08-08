import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Product provenance contract for the Experiment One handoff.
/// Software monotonic ordering only; no BLE/RF emission time or physical ES80 claim.
struct ForegroundCoreBluetoothCaptureControllerExperimentOnePostAdmissionRediscoveryTests {
    private static func source(named filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent("Sources").appendingPathComponent("NembraBluetoothCapture").appendingPathComponent(filename), encoding: .utf8)
    }

    @Test("sealed admission carries producer-issued monotonic handoff chronology")
    func chronology() throws {
        let run = try Self.source(named: "PassiveBluetoothExperimentOneRun.swift")
        let controller = try Self.source(named: "ForegroundCoreBluetoothCaptureController.swift")
        #expect(run.contains("let issuedAtUptimeNanoseconds: UInt64"))
        #expect(run.contains("DispatchTime.now().uptimeNanoseconds"))
        let start = try #require(controller.range(of: "func connectUsingExperimentOneAdmission("))
        let end = try #require(controller.range(of: "public func cancelActiveConnection()", range: start.upperBound..<controller.endIndex))
        let body = controller[start.lowerBound..<end.lowerBound]
        let freshness = try #require(body.range(of: "receivedAtUptimeNanoseconds >= payload.issuedAtUptimeNanoseconds"))
        let select = try #require(body.range(of: "targetState.selectTarget(payload.peripheralIdentifier)"))
        let install = try #require(body.range(of: "recorder = payload.recorder"))
        #expect(freshness.lowerBound < select.lowerBound)
        #expect(freshness.lowerBound < install.lowerBound)
    }
}
