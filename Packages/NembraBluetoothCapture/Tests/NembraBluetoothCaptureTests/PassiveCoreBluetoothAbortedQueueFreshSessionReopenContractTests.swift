import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red composition contract for the one remaining abort-recovery authority seam:
/// producer-issued FIFO resolution must be consumed by the queue gate before one exact
/// fresh durable target session may begin Ready again.
///
/// This is software lifecycle authority only. It does not establish physical ES80 truth.
@Suite("Aborted queue resolved fresh-session reopen contract")
struct PassiveCoreBluetoothAbortedQueueFreshSessionReopenContractTests {
    private static func gateSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources")
                .appendingPathComponent("NembraBluetoothCapture")
                .appendingPathComponent("PassiveCoreBluetoothObservationBoundaryQueueGate.swift"),
            encoding: .utf8
        )
    }

    @Test("abort quarantine can reopen only by consuming resolved FIFO authority")
    func resolutionReceiptIsMechanicalReopenAuthority() throws {
        let source = try Self.gateSource()

        #expect(source.contains("reopenAfterAbortedQueueResolution("))
        #expect(source.contains("PassiveCoreBluetoothAbortedQueueResolution.Receipt"))
        #expect(source.contains("requiredReadyTargetSessionGeneration"))
        #expect(source.contains("freshTargetSessionGeneration"))
    }

    @Test("ordinary reset cannot erase the exact fresh-session bind")
    func resetDoesNotBypassFreshSessionAuthority() throws {
        let source = try Self.gateSource()

        let resetStart = try #require(
            source.range(of: "    mutating func resetForNewCaptureSession() -> Bool {")?.lowerBound
        )
        let resetSection = source[resetStart...]
        #expect(!resetSection.prefix(500).contains("requiredReadyTargetSessionGeneration = nil"))
    }

    @Test("Ready admission consumes the exact bound fresh target session")
    func nextReadyIsBoundToExactFreshGeneration() throws {
        let source = try Self.gateSource()
        let beginStart = try #require(
            source.range(of: "    mutating func begin(\n        _ boundaryKind: BoundaryKind")?.lowerBound
        )
        let beginEnd = try #require(
            source.range(of: "    /// Opens Horizon", range: beginStart..<source.endIndex)?.lowerBound
        )
        let beginSection = source[beginStart..<beginEnd]

        #expect(beginSection.contains("requiredReadyTargetSessionGeneration"))
        #expect(beginSection.contains("authority.targetSessionGeneration"))
    }
}
