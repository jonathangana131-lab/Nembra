import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red source contract for the complete CoreBluetooth callback surface after
/// observation-Horizon admission.
///
/// Once the queue gate enters drainingHorizon, the accepted artifact interval is fixed.
/// Evidence-producing callbacks may not mutate acquisition state, restart discovery,
/// advance artifact authority, or poison an otherwise legitimate closing capture via
/// `failCapture(...)`. Transport-only cleanup is a separate policy.
///
/// This test deliberately does not patch the high-contention controller. A future
/// controller may replace these source checks with stronger behavioral/injected tests,
/// but it must preserve an equivalent whole-callback admission invariant.
struct ForegroundCoreBluetoothCaptureControllerPostHorizonCallbackIsolationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let controller = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift")
        return try String(contentsOf: controller, encoding: .utf8)
    }

    private static func section(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> Substring {
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test("Horizon admission fences every evidence-producing CoreBluetooth callback before artifact mutation")
    func postHorizonCallbacksFailClosedBeforeEvidenceMutation() throws {
        let source = try Self.controllerSource()

        let callbacks: [(start: String, end: String, firstRisk: String)] = [
            (
                "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,",
                "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {",
                "let receipt = callbackReceipt()"
            ),
            (
                "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {",
                "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,",
                "connectionTimeoutTask?.cancel()"
            ),
            (
                "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,",
                "    public func centralManager(\n        _ central: CBCentralManager,\n        didDisconnectPeripheral peripheral: CBPeripheral,",
                "if !acquisitionLedger.isReady {"
            ),
            (
                "    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,",
                "if let error {"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,",
                "if let error {"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,",
                "if let error {"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,",
                "if let error {"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,",
                "let key: PassiveCoreBluetoothTargetState.AttributeKey"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,",
                "    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {",
                "let key: PassiveCoreBluetoothTargetState.AttributeKey"
            )
        ]

        for callback in callbacks {
            let body = try Self.section(
                in: source,
                from: callback.start,
                to: callback.end
            )
            let horizonFence = try Self.offset(
                of: "observationBoundaryBlocksArtifactMutation",
                in: body
            )
            let firstRisk = try Self.offset(of: callback.firstRisk, in: body)
            #expect(horizonFence < firstRisk)
        }
    }

    @Test("post-H selected-target callback errors cannot reach capture failure")
    func postHorizonEvidenceCallbacksFenceBeforeFailurePaths() throws {
        let source = try Self.controllerSource()

        let callbacks: [(start: String, end: String)] = [
            (
                "    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,",
                "    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {"
            )
        ]

        for callback in callbacks {
            let body = try Self.section(in: source, from: callback.start, to: callback.end)
            let horizonFence = try Self.offset(
                of: "observationBoundaryBlocksArtifactMutation",
                in: body
            )
            let failure = try Self.offset(of: "failCapture(", in: body)
            #expect(horizonFence < failure)
        }
    }
}
