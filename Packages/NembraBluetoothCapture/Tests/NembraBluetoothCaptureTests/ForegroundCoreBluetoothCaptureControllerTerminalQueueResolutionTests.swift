import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Foreground-controller composition contract for terminal post-H FIFO chronology.
/// Retired queue positions are resolved, not recorder-written evidence.
struct ForegroundCoreBluetoothCaptureControllerTerminalQueueResolutionTests {
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

    @Test("terminal cleanup uses exact retirement then explicit resolution")
    func terminalCleanupConsumesBothProducerReceipts() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "    private func resolveQueuedEvidenceAfterTerminalHorizon() throws")?.lowerBound)
        let end = try #require(source.range(of: "    private func scheduleConnectionTimeout", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let retirement = try #require(section.range(of: "PassiveCoreBluetoothTerminalQueueRetirement.retire(")?.lowerBound)
        let resolution = try #require(section.range(of: "PassiveCoreBluetoothTerminalQueueResolution.resolve(")?.lowerBound)
        let frontierAdvance = try #require(section.range(of: "lastResolvedEventSequence = resolution.resolvedThroughQueueSequence")?.lowerBound)

        #expect(section.distance(from: section.startIndex, to: retirement) < section.distance(from: section.startIndex, to: resolution))
        #expect(section.distance(from: section.startIndex, to: resolution) < section.distance(from: section.startIndex, to: frontierAdvance))
        #expect(!section.contains("pendingEvents.removeAll"))
    }

    @Test("recorder-written and globally-resolved frontiers are distinct")
    func retiredEventsDoNotBecomeRecorderWritten() throws {
        let source = try Self.controllerSource()
        #expect(source.contains("private var lastProcessedEventSequence: UInt64 = 0"))
        #expect(source.contains("private var lastResolvedEventSequence: UInt64 = 0"))

        let start = try #require(source.range(of: "    private func resolveQueuedEvidenceAfterTerminalHorizon() throws")?.lowerBound)
        let end = try #require(source.range(of: "    private func scheduleConnectionTimeout", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]
        #expect(!section.contains("lastProcessedEventSequence ="))
    }

    @Test("sealed artifact survives post-freeze lifecycle cleanup failure")
    func finalizedArtifactAuthorityPrecedesFallibleTerminalResolution() throws {
        let source = try Self.controllerSource()
        let start = try #require(source.range(of: "    public func encodedFinalizedObservationHorizonJSON(")?.lowerBound)
        let end = try #require(source.range(of: "    private func beginTargetSessionIfNeeded", range: start..<source.endIndex)?.lowerBound)
        let section = source[start..<end]

        let freeze = try #require(section.range(of: "committedHorizon.completeHorizonArtifactFreeze")?.lowerBound)
        let finalizedAuthority = try #require(section.range(of: "lastFinalizedArtifactAuthority = committedHorizon.authority")?.lowerBound)
        let cleanup = try #require(section.range(of: "resolveQueuedEvidenceAfterTerminalHorizon()")?.lowerBound)
        let returnData = try #require(section.range(of: "return data")?.lowerBound)

        #expect(section.distance(from: section.startIndex, to: freeze) < section.distance(from: section.startIndex, to: finalizedAuthority))
        #expect(section.distance(from: section.startIndex, to: finalizedAuthority) < section.distance(from: section.startIndex, to: cleanup))
        #expect(section.distance(from: section.startIndex, to: cleanup) < section.distance(from: section.startIndex, to: returnData))
    }
}