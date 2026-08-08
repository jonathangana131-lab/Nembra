import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red source contract for the incumbent foreground controller's sealed
/// terminal lifecycle.
///
/// The terminal Horizon already prevents new recorder enqueue. These checks pin the
/// adjacent requirement: later CoreBluetooth transport callbacks may clean up live
/// transport state, but they must not advance the immutable artifact authority or
/// restart finite GATT acquisition inside the already-sealed recorder lifecycle.
///
/// This is intentionally test-only coordination evidence. A future controller may
/// replace these source checks with stronger behavioral coverage when its CoreBluetooth
/// dependency is injectable, but the terminal truth invariant must remain equivalent.
struct ForegroundCoreBluetoothCaptureControllerTerminalTransportIsolationTests {
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

    @Test("terminal GATT invalidation cannot advance authority or restart discovery")
    func serviceInvalidationIsTransportOnlyAfterTerminalFreeze() throws {
        let source = try Self.controllerSource()
        let callback = try Self.section(
            in: source,
            from: "    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {",
            to: "\n    }\n}"
        )

        // The callback must branch on the sealed terminal lifecycle before either
        // authority replacement or finite acquisition restart is reachable.
        let terminalFence = try Self.offset(
            of: "observationBoundaryQueueGate.isTerminal",
            in: callback
        )
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: callback)
        let rediscovery = try Self.offset(of: "beginDiscovery(on: peripheral)", in: callback)

        #expect(terminalFence < authorityAdvance)
        #expect(terminalFence < rediscovery)
    }

    @Test("terminal disconnect cleanup cannot revoke finalized artifact authority")
    func disconnectSeparatesTransportCleanupFromArtifactAuthority() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func handleDisconnect(",
            to: "}\n\nextension ForegroundCoreBluetoothCaptureController: @preconcurrency CBCentralManagerDelegate"
        )

        let terminalFence = try Self.offset(
            of: "observationBoundaryQueueGate.isTerminal",
            in: method
        )
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)

        #expect(terminalFence < authorityAdvance)
    }

    @Test("terminal central-state cleanup cannot revoke finalized artifact authority")
    func centralStateChangeSeparatesTransportCleanupFromArtifactAuthority() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func centralManagerDidUpdateState(_ central: CBCentralManager) {",
            to: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDiscover peripheral: CBPeripheral,"
        )

        let terminalFence = try Self.offset(
            of: "observationBoundaryQueueGate.isTerminal",
            in: method
        )
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)

        #expect(terminalFence < authorityAdvance)
    }

    @Test("terminal evidence enqueue remains closed before queue sequence allocation")
    func terminalRecorderEvidenceRemainsImmutable() throws {
        let source = try Self.controllerSource()
        let enqueue = try Self.section(
            in: source,
            from: "    private func enqueue(\n        _ event: PassiveBluetoothCaptureEvent,\n        receivedAtUptimeNanoseconds:",
            to: "    private func enqueueInterruption("
        )

        let terminalGuard = try Self.offset(
            of: "guard !observationBoundaryQueueGate.isTerminal else { return }",
            in: enqueue
        )
        let sequenceAllocation = try Self.offset(of: "lastEnqueuedEventSequence += 1", in: enqueue)

        #expect(terminalGuard < sequenceAllocation)
    }
}
