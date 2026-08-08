import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

/// Expected-red coordination coverage for the durable-Horizon append -> queue-commit
/// interlock. Ready already has a producer-issued recovery token for the analogous
/// actor-reentrancy state; Horizon currently does not.
///
/// This file deliberately changes no production source. It proves the existing
/// durable partial state and pins the minimum source shape needed for an owning
/// lifecycle successor to recover it without pretending the Horizon append never
/// happened.
@Suite("Passive CoreBluetooth Horizon append/commit reentrancy")
struct PassiveCoreBluetoothHorizonCommitReentrancyTests {
    private let authority = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    @Test("durable Horizon append survives authority change before queue commit")
    @MainActor
    func durableHorizonAppendThenAuthorityAdvanceLeavesTypedPartialState() async throws {
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authority)
        var gate = PassiveCoreBluetoothObservationBoundaryQueueGate()

        let readyAdmission = try PassiveCoreBluetoothObservationBoundaryTransactionDecision.beginReady(
            queueCutoff: 0,
            processedThrough: 0,
            authorityFence: fence,
            gate: &gate
        )
        let recordedReady = try await readyAdmission.recordBoundary(on: recorder)
        let committedReady = try recordedReady.markBoundaryRecorded(
            on: &gate,
            lastProcessedQueueSequence: 0
        )

        let horizonAdmission = try committedReady.beginHorizon(
            queueCutoff: 0,
            processedThrough: 0,
            gate: &gate
        )
        let recordedHorizon = try await horizonAdmission.recordBoundary(on: recorder)
        let activeHorizon = try #require(gate.activeTransaction)

        let afterAppend = await recorder.snapshot()
        #expect(afterAppend.observationBoundaries.count == 2)
        #expect(gate.phase == .drainingHorizon(activeHorizon))

        let replacementAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authority.targetSessionGeneration,
            authorityGeneration: authority.authorityGeneration + 1
        )
        try fence.transition(from: authority, to: replacementAuthority)

        #expect(throws: PassiveCoreBluetoothObservationBoundaryQueueGate.StateError.authorityChanged) {
            _ = try recordedHorizon.markBoundaryRecorded(
                on: &gate,
                lastProcessedQueueSequence: 0
            )
        }

        // The recorder has durably accepted H, while the queue gate still owns the
        // pre-commit Horizon transaction. This state must never be mislabeled as a
        // zero-mutation rejection or silently reset.
        #expect((await recorder.snapshot()).observationBoundaries.count == 2)
        #expect(gate.phase == .drainingHorizon(activeHorizon))
        #expect(!gate.resetForNewCaptureSession())
    }

    @Test("recorded Horizon exposes exact producer identity and a distinct recovery entry")
    func recordedHorizonHasTypedRecoveryContract() throws {
        let transactionSource = try Self.productionSource(
            named: "PassiveCoreBluetoothObservationBoundaryTransactionDecision.swift"
        )
        let recordedHorizon = try Self.section(
            in: transactionSource,
            from: "    struct RecordedHorizonBoundary: Equatable, Sendable {",
            to: "    struct CommittedHorizonBoundary: Equatable, Sendable {"
        )

        // Recovery must consume the exact producer-issued Horizon transaction, not
        // reconstruct authority from scalar cutoff/context values after the fact.
        #expect(recordedHorizon.contains("var transactionRevision"))
        #expect(recordedHorizon.contains("var transactionIdentity"))

        let gateSource = try Self.productionSource(
            named: "PassiveCoreBluetoothObservationBoundaryQueueGate.swift"
        )
        #expect(gateSource.contains("abortRecordedHorizonBeforeGateCommit("))
    }

    private static func productionSource(named fileName: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let packageRoot = testFile
            .deletingLastPathComponent() // NembraBluetoothCaptureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let source = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("NembraBluetoothCapture")
            .appendingPathComponent(fileName)
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
}
