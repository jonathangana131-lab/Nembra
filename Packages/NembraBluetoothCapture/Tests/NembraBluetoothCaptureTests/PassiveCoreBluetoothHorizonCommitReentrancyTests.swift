import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth Horizon append/commit reentrancy")
struct PassiveCoreBluetoothHorizonCommitReentrancyTests {
    private let authorityA = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private var authorityB: PassiveCoreBluetoothArtifactAuthorityContext {
        PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityA.authorityGeneration + 1
        )
    }

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private static func packageSource(_ filename: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let source = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent(filename)
        return try String(contentsOf: source, encoding: .utf8)
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

    @Test("durable Horizon append cannot be left without exact recovery after authority change")
    @MainActor
    func durableHorizonAppendThenAuthorityAdvanceRequiresExactRecovery() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let ready = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await ready.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )
        let horizon = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let recordedHorizon = try await horizon.recordBoundary(on: recorder)
        let activeHorizon = try #require(gate.activeTransaction)

        let afterAppend = await recorder.snapshot()
        #expect(afterAppend.observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.phase == .drainingHorizon(activeHorizon))

        try fence.transition(from: authorityA, to: authorityB)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try recordedHorizon.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
        }

        // The durable Horizon evidence is still present, but the queue transaction is
        // stranded before `.horizonBoundaryRecorded` / exact-H artifact freeze.
        #expect((await recorder.snapshot()).observationBoundaries.map(\.kind) == [
            .finiteAcquisitionReady,
            .observationHorizon
        ])
        #expect(gate.phase == .drainingHorizon(activeHorizon))
        #expect(!gate.isTerminal)
        #expect(!gate.resetForNewCaptureSession())

        // Expected-red integration contract: a producer-issued recorded-Horizon token
        // needs the same exact transaction revision+UUID identity that recorded Ready
        // already exposes, so recovery cannot accept equal-valued foreign state.
        let decisionSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryTransactionDecision.swift"
        )
        let recordedHorizonSection = try Self.section(
            in: decisionSource,
            from: "    struct RecordedHorizonBoundary: Equatable, Sendable {",
            to: "    struct CommittedHorizonBoundary: Equatable, Sendable {"
        )
        #expect(recordedHorizonSection.contains("var transactionRevision: UInt64"))
        #expect(recordedHorizonSection.contains("var transactionIdentity: UUID"))

        // Expected-red integration contract: the queue gate needs a distinct exact
        // recovery entry for append-success/commit-failure Horizon. It must not reuse
        // zero-mutation rejection or successful-terminal retirement authority.
        let gateSource = try Self.packageSource(
            "PassiveCoreBluetoothObservationBoundaryQueueGate.swift"
        )
        #expect(gateSource.contains("abortRecordedHorizonBeforeGateCommit"))
        #expect(gateSource.contains("recordedHorizonInvalidatedBeforeGateCommit"))
    }
}
