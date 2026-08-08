import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller retired terminal callback isolation")
struct ForegroundCoreBluetoothCaptureControllerRetiredTerminalCallbackIsolationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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

    @Test("post-H cancellation marks terminal callback transport-only before retiring attempt")
    func finalizedCancellationMarksRetiredCallbackBeforeRetirement() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func cancelActiveConnection(cause: PassiveCoreBluetoothCancellationCause) {",
            to: "    /// Adds a human-observed stock-app value"
        )
        let closingFence = try Self.offset(of: "if observationBoundaryBlocksArtifactMutation", in: method)
        let mark = try Self.offset(
            of: "transportOnlyTerminalCallbackIdentifiers.insert(peripheral.identifier)",
            in: method
        )
        let retirement = try Self.offset(of: "targetState.retireActiveAttempt()", in: method)
        #expect(closingFence < mark)
        #expect(mark < retirement)
    }

    @Test("retired disconnect is consumed before fresh evidence or authority mutation")
    func retiredDisconnectCannotEnterFreshRecorder() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    private func handleDisconnect(",
            to: "}\n\nextension ForegroundCoreBluetoothCaptureController: @preconcurrency CBCentralManagerDelegate"
        )
        let consume = try Self.offset(
            of: "transportOnlyTerminalCallbackIdentifiers.remove(identifier)",
            in: method
        )
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)
        let enqueue = try Self.offset(of: "enqueue(", in: method)
        #expect(consume < authorityAdvance)
        #expect(consume < enqueue)
    }

    @Test("retired failed-connect is consumed before fresh evidence or authority mutation")
    func retiredFailedConnectCannotEnterFreshRecorder() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,",
            to: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDisconnectPeripheral peripheral: CBPeripheral,"
        )
        let consume = try Self.offset(
            of: "transportOnlyTerminalCallbackIdentifiers.remove(identifier)",
            in: method
        )
        let authorityAdvance = try Self.offset(of: "advanceArtifactAuthority()", in: method)
        let enqueue = try Self.offset(of: "enqueue(", in: method)
        #expect(consume < authorityAdvance)
        #expect(consume < enqueue)
    }

    @Test("every post-H attempt retirement path marks its future terminal callback transport-only")
    func allClosingRetirementsCarryTransportOnlyMarker() throws {
        let source = try Self.controllerSource()
        #expect(source.components(separatedBy: "transportOnlyTerminalCallbackIdentifiers.insert").count - 1 == 4)
        #expect(source.components(separatedBy: "transportOnlyTerminalCallbackIdentifiers.remove(identifier)").count - 1 == 2)
    }
}
