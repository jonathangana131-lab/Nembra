import Foundation
import Testing
@testable import NembraBluetoothCapture

struct ForegroundCoreBluetoothCaptureControllerRecoveryContractTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NembraBluetoothCapture package root
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
        let end = try #require(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test
    func stockAppMarkerFailsClosedDuringSelectedTargetTerminalQuarantine() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public func recordStockAppObservation(",
            to: "    public func captureSnapshot() async throws"
        )

        let targetAuthorityOffset = try Self.offset(
            of: "let selectedTargetIdentifier = targetState.selectedTargetIdentifier",
            in: body
        )
        let pendingGuardOffset = try Self.offset(
            of: "guard !selectedTargetCancellationPending else {",
            in: body
        )
        let quarantineErrorOffset = try Self.offset(
            of: "throw ControllerError.peripheralAwaitingTerminalCallback(selectedTargetIdentifier)",
            in: body
        )
        let observationOffset = try Self.offset(
            of: "let observation = try PassiveBluetoothStockAppObservation(",
            in: body
        )
        let enqueueOffset = try Self.offset(
            of: "enqueue(.stockAppState(observation))",
            in: body
        )

        #expect(targetAuthorityOffset < pendingGuardOffset)
        #expect(pendingGuardOffset < quarantineErrorOffset)
        #expect(quarantineErrorOffset < observationOffset)
        #expect(quarantineErrorOffset < enqueueOffset)
    }

    @Test
    func discoveryAdmissionRequiresControllerIntentAndCoreBluetoothCurrentScanState() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,",
            to: "    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral)"
        )

        let admissionOffset = try Self.offset(
            of: "guard PassiveCoreBluetoothDiscoveryAdmissionPolicy.accepts(",
            in: body
        )
        let managerIdentityOffset = try Self.offset(
            of: "callbackIsFromActiveManager: central === centralManager",
            in: body
        )
        let poweredOnOffset = try Self.offset(
            of: "isPoweredOn: central.state == .poweredOn",
            in: body
        )
        let currentScanOffset = try Self.offset(
            of: "isScanning: isScanning && central.isScanning",
            in: body
        )
        let receiptOffset = try Self.offset(of: "let receipt = callbackReceipt()", in: body)
        let candidateMutationOffset = try Self.offset(
            of: "peripheralByIdentifier[peripheral.identifier] = peripheral",
            in: body
        )

        #expect(admissionOffset < managerIdentityOffset)
        #expect(managerIdentityOffset < poweredOnOffset)
        #expect(poweredOnOffset < currentScanOffset)
        #expect(currentScanOffset < receiptOffset)
        #expect(currentScanOffset < candidateMutationOffset)
    }
}
