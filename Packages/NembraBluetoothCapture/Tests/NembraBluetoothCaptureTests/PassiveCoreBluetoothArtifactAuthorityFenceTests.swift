import Testing
@testable import NembraBluetoothCapture

@Suite("Passive CoreBluetooth artifact-authority fence")
struct PassiveCoreBluetoothArtifactAuthorityFenceTests {
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
    func transitionedAuthorityRejectsStaleMutation() throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        try fence.transition(from: authorityA, to: authorityB)

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

    @Test("stale transition cannot overwrite or rewind a newer authority")
    func staleTransitionCannotOverwriteNewerAuthority() throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        try fence.transition(from: authorityA, to: authorityB)

        let attemptedReplacement = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration,
            authorityGeneration: authorityB.authorityGeneration + 1
        )
        let error = capturedStateError {
            try fence.transition(from: authorityA, to: attemptedReplacement)
        }

        #expect(
            error == .authorityChanged(
                expected: authorityA,
                current: authorityB
            )
        )

        var stillOwnedByB = false
        try fence.withCurrentAuthority(authorityB) {
            stillOwnedByB = true
        }
        #expect(stillOwnedByB)
    }

    @Test("full target-session identity participates in the authority fence")
    func targetSessionReplacementRejectsOldSessionMutation() throws {
        let fence = PassiveCoreBluetoothArtifactAuthorityFence(authority: authorityA)
        let replacementSessionAuthority = PassiveCoreBluetoothArtifactAuthorityContext(
            targetSessionGeneration: authorityA.targetSessionGeneration + 1,
            authorityGeneration: 1
        )
        try fence.transition(
            from: authorityA,
            to: replacementSessionAuthority
        )

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
