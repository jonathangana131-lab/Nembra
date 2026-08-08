import Foundation
import NembraCore
import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth artifact-authority fence")
struct PassiveCoreBluetoothArtifactAuthorityFenceTests {
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

    private var authorityB: PassiveCoreBluetoothArtifactAuthorityContext {
        PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityA.authorityGeneration + 1
        )
    }

    @Test("current authority admits one synchronous mutation")
    func currentAuthorityAdmitsMutation() throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        var mutationCount = 0

        let value = try fence.withCurrentAuthority(authorityA) {
            mutationCount += 1
            return 42
        }

        #expect(value == 42)
        #expect(mutationCount == 1)
    }

    @Test("authority transition wins before stale mutation body can execute")
    func transitionedAuthorityRejectsStaleMutation() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        try await MainActor.run {
            try fence.transition(from: authorityA, to: authorityB)
        }

        var staleMutationExecuted = false
        let error = capturedStateError {
            _ = try fence.withCurrentAuthority(authorityA) {
                staleMutationExecuted = true
            }
        }

        #expect(
            error == .authorityChanged(
                expected: authorityA,
                current: authorityB
            )
        )
        #expect(!staleMutationExecuted)

        var currentMutationExecuted = false
        try fence.withCurrentAuthority(authorityB) {
            currentMutationExecuted = true
        }
        #expect(currentMutationExecuted)
    }

    @Test("stale authority transition cannot overwrite a newer authority")
    func staleTransitionCannotOverwriteNewerAuthority() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        try await MainActor.run {
            try fence.transition(from: authorityA, to: authorityB)
        }

        let attemptedReplacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityB.authorityGeneration + 1
        )
        var transitionError: PassiveCoreBluetoothArtifactAuthorityFence.StateError?
        do {
            try await MainActor.run {
                try fence.transition(from: authorityA, to: attemptedReplacement)
            }
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            transitionError = error
        }

        #expect(
            transitionError == .authorityChanged(
                expected: authorityA,
                current: authorityB
            )
        )
        let currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == authorityB)
    }

    @Test("same or same-session backward authority cannot become current again")
    func nonAdvancingSameSessionTransitionsFailClosed() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)

        var unchangedError: PassiveCoreBluetoothArtifactAuthorityFence.StateError?
        do {
            try await MainActor.run {
                try fence.transition(from: authorityA, to: authorityA)
            }
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            unchangedError = error
        }
        #expect(
            unchangedError == .nonAdvancingTransition(
                from: authorityA,
                to: authorityA
            )
        )
        var currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == authorityA)

        try await MainActor.run {
            try fence.transition(from: authorityA, to: authorityB)
        }

        var resurrectionError: PassiveCoreBluetoothArtifactAuthorityFence.StateError?
        do {
            try await MainActor.run {
                try fence.transition(from: authorityB, to: authorityA)
            }
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            resurrectionError = error
        }
        #expect(
            resurrectionError == .nonAdvancingTransition(
                from: authorityB,
                to: authorityA
            )
        )
        currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == authorityB)
    }

    @Test("strictly newer target session may start its own authority counter")
    func newerTargetSessionMayResetAuthorityCounter() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        let replacementSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration + 1,
            authorityGeneration: 1
        )

        try await MainActor.run {
            try fence.transition(
                from: authorityA,
                to: replacementSessionAuthority
            )
        }

        let currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == replacementSessionAuthority)

        var oldSessionMutationExecuted = false
        let error = capturedStateError {
            try fence.withCurrentAuthority(authorityA) {
                oldSessionMutationExecuted = true
            }
        }
        #expect(
            error == .authorityChanged(
                expected: authorityA,
                current: replacementSessionAuthority
            )
        )
        #expect(!oldSessionMutationExecuted)

        var replacementMutationExecuted = false
        try fence.withCurrentAuthority(replacementSessionAuthority) {
            replacementMutationExecuted = true
        }
        #expect(replacementMutationExecuted)
    }

    @Test("older target session cannot resurrect even with a larger authority counter")
    func olderTargetSessionCannotResurrect() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        let newerSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        try await MainActor.run {
            try fence.transition(from: authorityA, to: newerSessionAuthority)
        }

        let attemptedOlderSession = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: UInt64.max
        )
        var transitionError: PassiveCoreBluetoothArtifactAuthorityFence.StateError?
        do {
            try await MainActor.run {
                try fence.transition(
                    from: newerSessionAuthority,
                    to: attemptedOlderSession
                )
            }
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            transitionError = error
        }

        #expect(
            transitionError == .nonAdvancingTransition(
                from: newerSessionAuthority,
                to: attemptedOlderSession
            )
        )
        let currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == newerSessionAuthority)
    }

    @Test("throwing mutation releases the fence without changing authority")
    func throwingMutationDoesNotPoisonFence() throws {
        enum MutationError: Error {
            case expected
        }

        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        do {
            try fence.withCurrentAuthority(authorityA) {
                throw MutationError.expected
            }
            Issue.record("Expected mutation error")
        } catch MutationError.expected {
            // Expected. The lock must be released by defer.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        var followupMutationExecuted = false
        try fence.withCurrentAuthority(authorityA) {
            followupMutationExecuted = true
        }
        #expect(followupMutationExecuted)
    }

    @Test("revoked decision leaves zero stale recorder boundaries")
    func revokedDecisionCannotMutateRecorder() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .finiteAcquisitionReady,
                queueCutoff: 0,
                processedThrough: 0,
                authority: authorityA
            )
        }

        try await MainActor.run {
            try fence.transition(from: authorityA, to: authorityB)
        }

        var rejection: PassiveCoreBluetoothArtifactAuthorityFence.StateError?
        do {
            try await decision.recordBoundary(
                on: recorder,
                authorityFence: fence
            )
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            rejection = error
        }

        #expect(
            rejection == .authorityChanged(
                expected: authorityA,
                current: authorityB
            )
        )
        let session = await recorder.snapshot()
        #expect(session.observationBoundaries.isEmpty)
    }

    @Test("current decision records exact pre-await clocks through authority fence")
    func currentDecisionRecordsWithoutClockResampling() async throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: es80,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let decision = try await MainActor.run {
            try PassiveCoreBluetoothObservationBoundaryDecision.capture(
                kind: .finiteAcquisitionReady,
                queueCutoff: 0,
                processedThrough: 0,
                authority: authorityA
            )
        }

        try await decision.recordBoundary(
            on: recorder,
            authorityFence: fence
        )

        let session = await recorder.snapshot()
        let boundary = try #require(session.observationBoundaries.first)
        #expect(session.observationBoundaries.count == 1)
        #expect(boundary.kind == .finiteAcquisitionReady)
        #expect(boundary.recordSequenceWatermark == 0)
        #expect(boundary.observedAtUptimeNanoseconds == decision.observedAtUptimeNanoseconds)
        #expect(boundary.observedAtDate == decision.observedAtDate)
        let currentAuthority = await MainActor.run { fence.currentAuthority }
        #expect(currentAuthority == authorityA)
    }

    private func capturedStateError(
        _ body: () throws -> Void
    ) -> PassiveCoreBluetoothArtifactAuthorityFence.StateError? {
        do {
            try body()
            return nil
        } catch let error as PassiveCoreBluetoothArtifactAuthorityFence.StateError {
            return error
        } catch {
            Issue.record("Unexpected error: \(error)")
            return nil
        }
    }
}
