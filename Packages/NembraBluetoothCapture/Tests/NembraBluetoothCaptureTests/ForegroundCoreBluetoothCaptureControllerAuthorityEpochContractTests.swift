import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Diagnostic source contract for the final Ready/Horizon controller composition.
///
/// A queued callback can outlive an artifact-authority transition while the recorder
/// hop is suspended. Target-session identity alone is therefore insufficient queue
/// ownership: every admitted `PendingEvent` must retain the exact artifact-authority
/// generation that was current synchronously at callback admission. The eventual
/// controller integration may then make generation/cutoff-specific decisions without
/// retrospectively sampling a newer authority after an `await`.
///
/// This contract is intentionally expected-red on the #411 dependency until the
/// incumbent controller-integration owner consumes the invariant. It does not prescribe
/// how the later Ready/Horizon retirement policy uses the captured epoch.
struct ForegroundCoreBluetoothCaptureControllerAuthorityEpochContractTests {
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

    @Test
    func pendingEventOwnsExactArtifactAuthorityGeneration() throws {
        let source = try Self.controllerSource()
        let pendingEvent = try Self.section(
            in: source,
            from: "    private struct PendingEvent {",
            to: "    /// Callback events are synchronously inserted"
        )

        #expect(pendingEvent.contains("let authorityGeneration: UInt64"))
    }

    @Test
    func enqueueSnapshotsAuthorityGenerationWithRecorderAndSession() throws {
        let source = try Self.controllerSource()
        let enqueue = try Self.section(
            in: source,
            from: "    private func enqueue(\n        _ event: PassiveBluetoothCaptureEvent,\n        receivedAtUptimeNanoseconds: UInt64,",
            to: "    private func enqueueInterruption("
        )

        #expect(enqueue.contains("recorder: recorder"))
        #expect(enqueue.contains("sessionGeneration: targetSessionGeneration"))
        #expect(enqueue.contains("authorityGeneration: artifactAuthorityGeneration"))
    }
}
