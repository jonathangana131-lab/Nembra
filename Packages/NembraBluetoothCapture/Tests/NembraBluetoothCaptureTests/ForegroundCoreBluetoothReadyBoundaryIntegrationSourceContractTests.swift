import Foundation
import Testing
@testable import NembraBluetoothCapture

/// Source-level regressions for the high-contention foreground controller's
/// finite-acquisition Ready integration.
///
/// These tests deliberately do not instantiate CoreBluetooth. They pin the
/// controller composition seams that are otherwise difficult to exercise without
/// a live CBCentralManager: accepted callback FIFO authority, pre-await boundary
/// ordering, Ready-gated product availability, and the six finite-acquisition
/// completion callbacks that can make the acquisition ledger become ready.
///
/// This is software lifecycle evidence only. It does not establish physical ES80
/// identity, RF completeness, GATT/Tuya semantics, or telemetry meaning.
struct ForegroundCoreBluetoothReadyBoundaryIntegrationSourceContractTests {
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
        let end = try #require(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return source[start..<end]
    }

    private static func offset(of needle: String, in haystack: Substring) throws -> Int {
        let range = try #require(haystack.range(of: needle))
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }

    @Test
    func completeEvidenceRequiresReadyForTheCurrentArtifactAuthority() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    public var hasCompleteTargetEvidence: Bool {",
            to: "    private let vehicleIdentity: VehicleIdentity"
        )

        let ledgerReady = try Self.offset(of: "acquisitionLedger.isReady", in: body)
        let readyAuthority = try Self.offset(
            of: "finiteAcquisitionReadyAuthority?.matches(",
            in: body
        )
        let targetGeneration = try Self.offset(
            of: "targetSessionGeneration: targetSessionGeneration",
            in: body
        )
        let authorityGeneration = try Self.offset(
            of: "authorityGeneration: artifactAuthorityGeneration",
            in: body
        )

        #expect(ledgerReady < readyAuthority)
        #expect(readyAuthority < targetGeneration)
        #expect(targetGeneration < authorityGeneration)
        #expect(body.contains(") == true"))
    }

    @Test
    func queuedCallbacksFreezeArtifactAuthorityAtAdmission() throws {
        let source = try Self.controllerSource()
        let pendingEvent = try Self.section(
            in: source,
            from: "    private struct PendingEvent {",
            to: "    /// Callback events are synchronously inserted"
        )
        #expect(pendingEvent.contains("let authority: PassiveCoreBluetoothArtifactAuthorityContext"))

        let enqueue = try Self.section(
            in: source,
            from: "    private func enqueue(\n        _ event: PassiveBluetoothCaptureEvent,\n        receivedAtUptimeNanoseconds: UInt64,",
            to: "    private func enqueueInterruption("
        )
        let sequenceAdvance = try Self.offset(
            of: "lastEnqueuedEventSequence += 1",
            in: enqueue
        )
        let pendingAppend = try Self.offset(of: "pendingEvents.append(", in: enqueue)
        let authorityCapture = try Self.offset(
            of: "authority: currentArtifactAuthority",
            in: enqueue
        )
        let drainStart = try Self.offset(of: "startDrainIfNeeded()", in: enqueue)

        #expect(sequenceAdvance < pendingAppend)
        #expect(pendingAppend < authorityCapture)
        #expect(authorityCapture < drainStart)
    }

    @Test
    func readyDecisionFreezesFIFOAndClockBeforeTheFirstAwait() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    private func beginFiniteAcquisitionReadyBoundaryIfNeeded() {",
            to: "    private func scheduleConnectionTimeout("
        )

        let readyGuard = try Self.offset(
            of: "case .awaitingReady = observationBoundaryQueueGate.phase",
            in: body
        )
        let decisionCapture = try Self.offset(
            of: "decision = try PassiveCoreBluetoothObservationBoundaryDecision.capture(",
            in: body
        )
        let queueCutoff = try Self.offset(
            of: "queueCutoff: lastEnqueuedEventSequence",
            in: body
        )
        let processedFrontier = try Self.offset(
            of: "processedThrough: lastProcessedEventSequence",
            in: body
        )
        let transactionBegin = try Self.offset(
            of: "transaction = try observationBoundaryQueueGate.begin(",
            in: body
        )
        let taskStart = try Self.offset(
            of: "observationBoundaryTask = Task { @MainActor",
            in: body
        )
        let firstAwait = try Self.offset(
            of: "await self.flushPendingEvents(through: decision.queueCutoff)",
            in: body
        )
        let recordBoundary = try Self.offset(
            of: "try await decision.recordBoundary(on: recorder)",
            in: body
        )
        let commitBoundary = try Self.offset(
            of: "try self.observationBoundaryQueueGate.markBoundaryRecorded(",
            in: body
        )
        let publishReadyAuthority = try Self.offset(
            of: "self.finiteAcquisitionReadyAuthority = decision.authority",
            in: body
        )

        #expect(readyGuard < decisionCapture)
        #expect(decisionCapture < queueCutoff)
        #expect(queueCutoff < processedFrontier)
        #expect(processedFrontier < transactionBegin)
        #expect(transactionBegin < taskStart)
        #expect(taskStart < firstAwait)
        #expect(firstAwait < recordBoundary)
        #expect(recordBoundary < commitBoundary)
        #expect(commitBoundary < publishReadyAuthority)
    }

    @Test
    func everyFiniteAcquisitionCompletionCallbackAttemptsReadyAdmission() throws {
        let source = try Self.controllerSource()
        let admission = "beginFiniteAcquisitionReadyBoundaryIfNeeded()"

        let callbackSections: [(String, String)] = [
            (
                "    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverIncludedServicesFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverCharacteristicsFor service: CBService,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didDiscoverDescriptorsFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateValueFor characteristic: CBCharacteristic,",
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,"
            ),
            (
                "    public func peripheral(\n        _ peripheral: CBPeripheral,\n        didUpdateNotificationStateFor characteristic: CBCharacteristic,",
                "    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {"
            ),
        ]

        for (start, end) in callbackSections {
            let body = try Self.section(in: source, from: start, to: end)
            let completion = try Self.offset(of: "acquisitionLedger.complete(", in: body)
            let refresh = try Self.offset(of: "refreshAcquisitionWatchdog()", in: body)
            let readyAdmission = try Self.offset(of: admission, in: body)

            #expect(completion < refresh)
            #expect(refresh < readyAdmission)
        }
    }

    @Test
    func normalRecorderDrainHonorsArtifactReadAndObservationBoundaryBarriers() throws {
        let source = try Self.controllerSource()
        let body = try Self.section(
            in: source,
            from: "    private func startDrainIfNeeded() {",
            to: "    private func flushPendingEvents(through watermark: UInt64) async {"
        )

        let artifactBarrier = try Self.offset(
            of: "artifactReadBarrier.permittedDrainUpperBound(",
            in: body
        )
        let observationBarrier = try Self.offset(
            of: "observationBoundaryQueueGate.permittedDrainUpperBound(",
            in: body
        )
        let minimum = try Self.offset(
            of: "min(artifactReadUpperBound, observationBoundaryUpperBound)",
            in: body
        )
        let removal = try Self.offset(of: "pendingEvents.removeFirst()", in: body)
        let recorderWrite = try Self.offset(of: "try await next.recorder.record(", in: body)
        let processedAdvance = try Self.offset(
            of: "self.lastProcessedEventSequence = max(",
            in: body
        )

        #expect(artifactBarrier < observationBarrier)
        #expect(observationBarrier < minimum)
        #expect(minimum < removal)
        #expect(removal < recorderWrite)
        #expect(recorderWrite < processedAdvance)
    }
}
