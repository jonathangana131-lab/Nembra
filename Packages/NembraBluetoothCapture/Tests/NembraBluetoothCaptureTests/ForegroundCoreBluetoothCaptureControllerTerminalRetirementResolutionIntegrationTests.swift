import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red integration contract for successful terminal Horizon cleanup.
///
/// A frozen H makes post-H callbacks intentionally outside the immutable artifact,
/// but deleting those queued callbacks directly is not enough: their global FIFO
/// positions become resolved-by-retirement, not recorder-written evidence. The live
/// controller must consume the package-owned terminal retirement and resolution
/// producers rather than treating `pendingEvents.removeAll` as lifecycle authority.
struct ForegroundCoreBluetoothCaptureControllerTerminalRetirementResolutionIntegrationTests {
    private static func controllerSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("ForegroundCoreBluetoothCaptureController.swift"),
            encoding: .utf8
        )
    }

    private static func finalizerSection(in source: String) throws -> Substring {
        let startMarker = "    public func encodedFinalizedObservationHorizonJSON("
        let endMarker = "\n    private func beginTargetSessionIfNeeded("
        let start = try #require(source.range(of: startMarker)?.lowerBound)
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    @Test("terminal cleanup consumes retirement then explicit resolved-by-retirement authority")
    func terminalCleanupCannotBeRawQueueDeletion() throws {
        let source = try Self.controllerSource()
        let finalizer = try Self.finalizerSection(in: source)

        let retirement = try #require(
            finalizer.range(of: "PassiveCoreBluetoothTerminalQueueRetirement.retire(")
        )
        let resolution = try #require(
            finalizer.range(of: "PassiveCoreBluetoothTerminalQueueResolution.resolve(")
        )

        #expect(retirement.lowerBound < resolution.lowerBound)
        #expect(!finalizer.contains("retireQueuedEvidenceAfterTerminalHorizon()"))
    }

    @Test("legacy terminal helper cannot delete pending FIFO directly")
    func legacyRawTerminalWipeIsRemoved() throws {
        let source = try Self.controllerSource()
        let helperMarker = "    private func retireQueuedEvidenceAfterTerminalHorizon()"

        #expect(!source.contains(helperMarker))
    }
}
