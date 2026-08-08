import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller observation-boundary integration")
struct ForegroundCoreBluetoothCaptureControllerObservationBoundaryIntegrationTests {
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

    @Test("queued evidence owns the artifact-authority epoch captured at enqueue")
    func pendingEventsCarryAuthorityEpoch() throws {
        let source = try Self.controllerSource()
        let pending = try Self.section(
            in: source,
            from: "    private struct PendingEvent {",
            to: "    /// Callback events are synchronously inserted"
        )
        #expect(pending.contains("let authority: PassiveCoreBluetoothArtifactAuthorityContext"))

        let enqueue = try Self.section(
            in: source,
            from: "    private func enqueue(\n        _ event: PassiveBluetoothCaptureEvent,\n        receivedAtUptimeNanoseconds:",
            to: "    private func enqueueInterruption("
        )
        #expect(enqueue.contains("authority: currentArtifactAuthorityContext()"))
    }

    @Test("finite acquisition readiness enters the boundary pipeline before watchdog rearm")
    func readyTransitionIsObservedSynchronously() throws {
        let source = try Self.controllerSource()
        let watchdog = try Self.section(
            in: source,
            from: "    private func refreshAcquisitionWatchdog() {",
            to: "    private func cancelAcquisitionWatchdog() {"
        )

        let readyOffset = try Self.offset(of: "if acquisitionLedger.isReady {", in: watchdog)
        let boundaryOffset = try Self.offset(of: "beginFiniteAcquisitionReadyBoundaryIfNeeded()", in: watchdog)
        let acquiringOffset = try Self.offset(of: "guard acquisitionLedger.phase == .acquiring", in: watchdog)
        #expect(readyOffset < boundaryOffset)
        #expect(boundaryOffset < acquiringOffset)
    }

    @Test("Ready cutoff, frontier, authority fence, and clocks are bound before the first await")
    func readyDecisionPrecedesActorHop() throws {
        let source = try Self.controllerSource()
        let pipeline = try Self.section(
            in: source,
            from: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded() {",
            to: "    private func requireForegroundEvidenceIntegrity() throws"
        )

        let admissionOffset = try Self.offset(
            of: "let admission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(",
            in: pipeline
        )
        let cutoffOffset = try Self.offset(of: "queueCutoff: lastEnqueuedEventSequence", in: pipeline)
        let frontierOffset = try Self.offset(of: "processedThrough: lastProcessedEventSequence", in: pipeline)
        let fenceOffset = try Self.offset(of: "authorityFence: artifactAuthorityFence", in: pipeline)
        let taskOffset = try Self.offset(of: "observationBoundaryTask = Task", in: pipeline)
        let awaitOffset = try Self.offset(of: "await self.flushPendingEvents(through: admission.queueCutoff)", in: pipeline)
        let recordOffset = try Self.offset(of: "admission.recordBoundaryWithMutationOutcome(on: recorder)", in: pipeline)
        let commitOffset = try Self.offset(of: "recordedReady.markBoundaryRecorded(", in: pipeline)

        #expect(admissionOffset < cutoffOffset)
        #expect(cutoffOffset < frontierOffset)
        #expect(frontierOffset < fenceOffset)
        #expect(fenceOffset < taskOffset)
        #expect(taskOffset < awaitOffset)
        #expect(awaitOffset < recordOffset)
        #expect(recordOffset < commitOffset)
    }

    @Test("normal FIFO drain honors both lifecycle and immutable-artifact cutoffs")
    func drainIntersectsBoundaryAndArtifactGates() throws {
        let source = try Self.controllerSource()
        let drain = try Self.section(
            in: source,
            from: "    private func startDrainIfNeeded() {",
            to: "    private func flushPendingEvents(through watermark: UInt64) async {"
        )

        let boundaryOffset = try Self.offset(
            of: "observationBoundaryQueueGate.permittedDrainUpperBound(",
            in: drain
        )
        let artifactOffset = try Self.offset(
            of: "artifactReadBarrier.permittedDrainUpperBound(",
            in: drain
        )
        let intersectionOffset = try Self.offset(
            of: "let drainThroughSequence = min(boundaryDrainUpperBound, artifactDrainUpperBound)",
            in: drain
        )
        let recorderOffset = try Self.offset(of: "try await next.recorder.record(", in: drain)

        #expect(boundaryOffset < intersectionOffset)
        #expect(artifactOffset < intersectionOffset)
        #expect(intersectionOffset < recorderOffset)
    }

    @Test("a fresh target cannot erase an already-started observation grammar")
    func targetSessionResetFailsClosedAfterReadyBegins() throws {
        let source = try Self.controllerSource()
        let session = try Self.section(
            in: source,
            from: "    private func beginTargetSessionIfNeeded(for identifier: UUID) throws {",
            to: "    private func currentArtifactContext() throws"
        )

        let resetOffset = try Self.offset(
            of: "guard observationBoundaryQueueGate.resetForNewCaptureSession() else {",
            in: session
        )
        let transitionOffset = try Self.offset(of: "try artifactAuthorityFence.transition(", in: session)
        let generationOffset = try Self.offset(
            of: "targetSessionGeneration = freshAuthority.targetSessionGeneration",
            in: session
        )
        let targetOffset = try Self.offset(of: "targetState.selectTarget(identifier)", in: session)
        #expect(resetOffset < transitionOffset)
        #expect(transitionOffset < generationOffset)
        #expect(generationOffset < targetOffset)
    }
}
