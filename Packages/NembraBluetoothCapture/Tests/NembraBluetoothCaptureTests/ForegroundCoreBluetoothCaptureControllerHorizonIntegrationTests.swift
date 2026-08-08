import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Foreground controller terminal Horizon integration")
struct ForegroundCoreBluetoothCaptureControllerHorizonIntegrationTests {
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

    @Test("Horizon admission requires a durably recorded Ready under current authority")
    func horizonAdmissionIsAuthorityBound() throws {
        let source = try Self.controllerSource()
        let admission = try Self.section(
            in: source,
            from: "    public var canFinalizeObservationHorizon: Bool {",
            to: "    private let vehicleIdentity"
        )

        #expect(admission.contains("hasCompleteTargetEvidence"))
        #expect(admission.contains("!artifactReadBarrier.isActive"))
        #expect(admission.contains("observationBoundaryTask == nil"))
        #expect(admission.contains("case .observing = observationBoundaryQueueGate.phase"))
        #expect(admission.contains("let committedReadyEpoch"))
        #expect(admission.contains("committedReadyEpoch.authority == artifactAuthorityFence.currentAuthority"))
        #expect(admission.contains("currentExperimentOneStatus(for: committedReadyEpoch)"))
    }

    @Test("terminal Horizon admission and gate transaction are synchronous before first await")
    func horizonDecisionPrecedesFirstAwait() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            to: "    private func completeTerminalFreshTargetSessionIfReady("
        )

        let permitOffset = try Self.offset(
            of: ".authorizeExperimentOneHorizon(for: committedReadyEpoch)",
            in: method
        )
        let admissionOffset = try Self.offset(
            of: "let horizonAdmission = try durationPermit.beginHorizon(",
            in: method
        )
        let cutoffOffset = try Self.offset(of: "queueCutoff: lastEnqueuedEventSequence", in: method)
        let frontierOffset = try Self.offset(of: "processedThrough: lastProcessedEventSequence", in: method)
        let gateOffset = try Self.offset(of: "gate: &observationBoundaryQueueGate", in: method)
        let firstAwaitOffset = try Self.offset(
            of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)",
            in: method
        )

        #expect(permitOffset < admissionOffset)
        #expect(admissionOffset < cutoffOffset)
        #expect(cutoffOffset < frontierOffset)
        #expect(frontierOffset < gateOffset)
        #expect(gateOffset < firstAwaitOffset)
    }

    @Test("Horizon drains exact prefix, records typed boundary, freezes JSON, then resolves post-H FIFO")
    func horizonPipelineFreezesBeforePostCutResolution() throws {
        let source = try Self.controllerSource()
        let method = try Self.section(
            in: source,
            from: "    public func encodedFinalizedObservationHorizonJSON(",
            to: "    private func completeTerminalFreshTargetSessionIfReady("
        )

        let flushOffset = try Self.offset(
            of: "await flushPendingEvents(through: horizonAdmission.queueCutoff)",
            in: method
        )
        let recordOffset = try Self.offset(
            of: ".recordBoundaryWithMutationOutcome(on: recorder)",
            in: method
        )
        let markOffset = try Self.offset(
            of: "recordedHorizon.markBoundaryRecorded(",
            in: method
        )
        let encodeOffset = try Self.offset(
            of: "data = try await recorder.encodedJSON(prettyPrinted: prettyPrinted)",
            in: method
        )
        let terminalOffset = try Self.offset(
            of: "committedHorizon.completeHorizonArtifactFreeze(",
            in: method
        )
        let finalizedAuthorityOffset = try Self.offset(
            of: "lastFinalizedArtifactAuthority = committedHorizon.authority",
            in: method
        )
        let resolutionOffset = try Self.offset(
            of: "let terminalResolution = try resolveQueuedEvidenceAfterTerminalHorizon()",
            in: method
        )
        let publishResolutionOffset = try Self.offset(
            of: "pendingTerminalQueueResolution = terminalResolution",
            in: method
        )

        #expect(flushOffset < recordOffset)
        #expect(recordOffset < markOffset)
        #expect(markOffset < encodeOffset)
        #expect(encodeOffset < terminalOffset)
        #expect(terminalOffset < finalizedAuthorityOffset)
        #expect(finalizedAuthorityOffset < resolutionOffset)
        #expect(resolutionOffset < publishResolutionOffset)
    }

    @Test("post-H FIFO retirement is authority-scoped and later callbacks cannot mutate sealed evidence")
    func sealedArtifactQuarantinesPostHorizonEvidence() throws {
        let source = try Self.controllerSource()
        let retirement = try Self.section(
            in: source,
            from: "    private func resolveQueuedEvidenceAfterTerminalHorizon() throws",
            to: "    private func scheduleConnectionTimeout"
        )
        #expect(retirement.contains("PassiveCoreBluetoothTerminalQueueRetirement.retire("))
        #expect(retirement.contains("queueSequence: pending.queueSequence"))
        #expect(retirement.contains("authority: pending.authority"))
        #expect(retirement.contains("PassiveCoreBluetoothTerminalQueueResolution.resolve("))
        #expect(retirement.contains("lastResolvedEventSequence = resolution.resolvedThroughQueueSequence"))

        let enqueue = try Self.section(
            in: source,
            from: "    private func enqueue(\n        _ event: PassiveBluetoothCaptureEvent,\n        receivedAtUptimeNanoseconds:",
            to: "    private func enqueueInterruption("
        )
        let terminalGuardOffset = try Self.offset(
            of: "guard !observationBoundaryQueueGate.isTerminal else { return }",
            in: enqueue
        )
        let sequenceOffset = try Self.offset(
            of: "lastEnqueuedEventSequence += 1",
            in: enqueue
        )
        #expect(terminalGuardOffset < sequenceOffset)
    }

    @Test("ordinary snapshots cannot race an in-flight lifecycle boundary")
    func artifactContextUsesOnlyStableBoundaryPhases() throws {
        let source = try Self.controllerSource()
        let context = try Self.section(
            in: source,
            from: "    private func currentArtifactContext() throws -> ArtifactContext {",
            to: "    private func validate(_ context: ArtifactContext) throws"
        )

        #expect(context.contains("case .observing:"))
        #expect(context.contains("eventWatermark = lastEnqueuedEventSequence"))
        #expect(context.contains("case .terminal:"))
        #expect(context.contains("terminalQueueCutoff"))
        #expect(context.contains("case .awaitingReady, .drainingReady, .abortQuarantined, .drainingHorizon, .horizonBoundaryRecorded:"))
        #expect(context.contains("throw ControllerError.captureIncomplete"))
    }

    @Test("transport teardown is authorized only after terminal artifact freeze")
    func finalizedTeardownRequiresTerminalGate() throws {
        let source = try Self.controllerSource()
        let teardown = try Self.section(
            in: source,
            from: "    public func teardownActiveConnectionAfterFinalization() throws {",
            to: "    private func cancelActiveConnection(cause:"
        )

        let terminalOffset = try Self.offset(
            of: "guard observationBoundaryQueueGate.isTerminal else {",
            in: teardown
        )
        let authorityOffset = try Self.offset(
            of: "guard let finalizedAuthority = lastFinalizedArtifactAuthority,",
            in: teardown
        )
        let transportOffset = try Self.offset(
            of: "cancelActiveConnection(cause: .finalizedArtifactTeardown)",
            in: teardown
        )
        #expect(terminalOffset < authorityOffset)
        #expect(authorityOffset < transportOffset)
    }
}
