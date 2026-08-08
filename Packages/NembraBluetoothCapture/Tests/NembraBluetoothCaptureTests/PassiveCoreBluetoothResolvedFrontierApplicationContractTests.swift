import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Expected-red authority contract for resolution-gated lifecycle reopen.
///
/// A queue-resolution receipt proves what the controller's globally-resolved frontier
/// may advance to; the producer does not mutate that controller state. Reopen therefore
/// must mechanically prove the returned frontier was actually applied before admitting
/// a fresh lifecycle. The consuming mutation must also remain on MainActor with the FIFO.
@Suite("Resolved frontier application before lifecycle reopen")
struct PassiveCoreBluetoothResolvedFrontierApplicationContractTests {
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

    @Test("aborted reopen requires the applied globally-resolved frontier")
    func abortedReopenCannotConsumeAnUnappliedResolution() throws {
        let source = try Self.gateSource()
        let start = try #require(
            source.range(of: "    mutating func reopenAfterAbortedQueueResolution(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    mutating func reopenAfterTerminalQueueResolution(",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let section = source[start..<end]

        #expect(section.contains("currentResolvedThroughQueueSequence"))
        #expect(section.contains(
            "currentResolvedThroughQueueSequence == resolution.resolvedThroughQueueSequence"
        ))
    }

    @Test("terminal reopen requires the applied globally-resolved frontier")
    func terminalReopenCannotConsumeAnUnappliedResolution() throws {
        let source = try Self.gateSource()
        let start = try #require(
            source.range(of: "    mutating func reopenAfterTerminalQueueResolution(")?.lowerBound
        )
        let end = try #require(
            source.range(
                of: "    @discardableResult\n    mutating func resetForNewCaptureSession()",
                range: start..<source.endIndex
            )?.lowerBound
        )
        let section = source[start..<end]

        #expect(section.contains("currentResolvedThroughQueueSequence"))
        #expect(section.contains(
            "currentResolvedThroughQueueSequence == resolution.resolvedThroughQueueSequence"
        ))
    }

    @Test("both resolution-consuming reopen transitions are MainActor-isolated")
    func reopenAuthorityCannotEscapeTheControllerFIFOExecutor() throws {
        let source = try Self.gateSource()

        #expect(source.contains(
            "@MainActor\n    mutating func reopenAfterAbortedQueueResolution("
        ))
        #expect(source.contains(
            "@MainActor\n    mutating func reopenAfterTerminalQueueResolution("
        ))
    }
}
