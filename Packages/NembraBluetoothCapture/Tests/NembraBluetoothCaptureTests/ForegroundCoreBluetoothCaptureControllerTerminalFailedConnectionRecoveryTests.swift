import Foundation
import Testing

@Suite("Foreground controller terminal failed-connection recovery")
struct ForegroundCoreBluetoothCaptureControllerTerminalFailedConnectionRecoveryTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    @Test("terminal didFailToConnect releases quarantine into the same fresh-session completion seam")
    func failedConnectionTerminalCallbackDrivesFreshSessionCompletion() throws {
        let source = try Self.controllerSource()
        let start = try #require(
            source.range(
                of: "    public func centralManager(\n        _ central: CBCentralManager,\n        didFailToConnect peripheral: CBPeripheral,"
            )?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    public func centralManager(\n        _ central: CBCentralManager,\n        didDisconnectPeripheral peripheral: CBPeripheral,",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let callback = source[start..<end]

        let consumeDisposition = try #require(
            callback.range(of: "targetState.completeFailedConnection(from: identifier)")
        )
        let terminalBranch = try #require(
            callback.range(of: "if observationBoundaryBlocksArtifactMutation")
        )
        let completion = try #require(
            callback.range(
                of: "completeTerminalFreshTargetSessionIfReady()",
                range: terminalBranch.upperBound..<callback.endIndex
            )
        )

        #expect(consumeDisposition.lowerBound < terminalBranch.lowerBound)
        #expect(terminalBranch.lowerBound < completion.lowerBound)
        #expect(callback[terminalBranch.lowerBound..<completion.lowerBound].contains("selectedTargetCancellationPending = false"))
    }
}
