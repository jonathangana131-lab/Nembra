import Foundation
import Testing
import NembraCore
@testable import NembraBluetoothCapture

@Suite("Artifact-authority recorder mutation gate")
struct PassiveCoreBluetoothArtifactAuthorityMutationGateTests {
    private let es80 = VehicleIdentity(
        manufacturer: "AOVOPRO",
        model: "ES80",
        displayName: "AOVOPRO ES80",
        protocolFamily: "Tuya / AOVOPRO (hardware validation pending)"
    )

    private let authorityA = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 11
    )

    private let authorityB = PassiveCoreBluetoothArtifactAuthorityContext(
        targetSessionGeneration: 7,
        authorityGeneration: 12
    )

    private func readyDecision(
        authority: PassiveCoreBluetoothArtifactAuthorityContext
    ) async throws -> PassiveCoreBluetoothObservationBoundaryDecision {
        try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .finiteAcquisitionReady,
                queueCutoff: 0,
                processedThrough: 0,
                authority: authority
            )
        }
    }

    @Test("authority advance before recorder mutation leaves zero stale boundaries")
    func authorityAdvanceDuringActorHopRejectsBeforeMutation() async throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityA
        )
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let decision = try await readyDecision(authority: authorityA)

        // Models the critical interleaving from the live controller: decision A is
        // already captured, then MainActor authority advances while the async path
        // has not yet entered the recorder's irreversible mutation point.
        try gate.transition(from: authorityA, to: authorityB)

        var rejection: PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError?
        do {
            try await decision.recordBoundary(on: recorder, mutationGate: gate)
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError {
            rejection = error
        }

        #expect(rejection == .authorityChanged)
        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.isEmpty)
    }

    @Test("current authority records exact pre-await decision clocks")
    func currentAuthorityRecordsDecisionWithoutClockResampling() async throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityA
        )
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let decision = try await readyDecision(authority: authorityA)

        try await decision.recordBoundary(on: recorder, mutationGate: gate)

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == decision.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == decision.observedAtDate)
        #expect(gate.snapshot() == authorityA)
    }

    @Test("stale authority transition fails atomically")
    func staleTransitionCannotReplaceCurrentAuthority() throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityA
        )
        let unrelated = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 99,
            authorityGeneration: 1
        )

        var rejection: PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError?
        do {
            try gate.transition(from: unrelated, to: authorityB)
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError {
            rejection = error
        }

        #expect(rejection == .staleTransitionSource)
        #expect(gate.snapshot() == authorityA)
    }

    @Test("no-op transition cannot masquerade as authority advance")
    func unchangedTransitionFailsClosed() throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityA
        )

        var rejection: PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError?
        do {
            try gate.transition(from: authorityA, to: authorityA)
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError {
            rejection = error
        }

        #expect(rejection == .unchangedAuthority)
        #expect(gate.snapshot() == authorityA)
    }

    @Test("retired authority cannot be resurrected")
    func authorityGenerationNeverMovesBackward() throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityA
        )
        try gate.transition(from: authorityA, to: authorityB)

        var rejection: PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError?
        do {
            try gate.transition(from: authorityB, to: authorityA)
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError {
            rejection = error
        }

        #expect(rejection == .nonMonotonicAuthority)
        #expect(gate.snapshot() == authorityB)
    }

    @Test("target-session generation cannot regress behind newer authority")
    func targetSessionGenerationNeverMovesBackward() throws {
        let gate = PassiveCoreBluetoothArtifactAuthorityMutationGate(
            initialAuthority: authorityB
        )
        let regressingTarget = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: 6,
            authorityGeneration: 13
        )

        var rejection: PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError?
        do {
            try gate.transition(from: authorityB, to: regressingTarget)
        } catch let error as PassiveCoreBluetoothArtifactAuthorityMutationGate.StateError {
            rejection = error
        }

        #expect(rejection == .nonMonotonicAuthority)
        #expect(gate.snapshot() == authorityB)
    }
}
