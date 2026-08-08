import Foundation
import NembraCore

/// A tiny synchronous serialization point shared by MainActor artifact-authority
/// transitions and recorder-actor lifecycle-boundary mutation.
///
/// The foreground controller's artifact authority can change while an async task
/// is suspended waiting to enter `PassiveCoreBluetoothCaptureRecorder`. A check on
/// MainActor before that `await` is therefore not enough: the old authority may be
/// invalid by the time the recorder actually mutates its session. Checking again
/// after the `await` is also too late because the boundary has already been
/// appended.
///
/// This gate makes the authority transition and the recorder's check+append share
/// one synchronous linearization domain. Whichever operation acquires the lock
/// first is authoritative:
/// - if an authority transition linearizes first, the stale recorder mutation is
///   rejected before it can append evidence;
/// - if a valid recorder mutation linearizes first, a later authority transition
///   occurs strictly after that mutation.
///
/// The protected operation must remain synchronous and must never perform an
/// `await` while the gate is held. This is software artifact-authority ordering
/// only; it establishes no physical ES80 identity or protocol truth.
final class PassiveCoreBluetoothArtifactAuthorityMutationGate: @unchecked Sendable {
    enum StateError: Error, Equatable, Sendable {
        case authorityChanged
        case staleTransitionSource
        case unchangedAuthority
    }

    private let lock = NSLock()
    private var currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext

    init(initialAuthority: PassiveCoreBluetoothArtifactAuthorityContext) {
        currentAuthority = initialAuthority
    }

    func snapshot() -> PassiveCoreBluetoothArtifactAuthorityContext {
        lock.lock()
        defer { lock.unlock() }
        return currentAuthority
    }

    /// Atomically replaces the current authority only when the caller still owns
    /// the exact authority it expects to retire. The controller should use this as
    /// the linearization point for every artifact-authority advance before it
    /// publishes the new generation to later asynchronous work.
    func transition(
        from expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        to newAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard currentAuthority == expectedAuthority else {
            throw StateError.staleTransitionSource
        }
        guard newAuthority != expectedAuthority else {
            throw StateError.unchangedAuthority
        }
        currentAuthority = newAuthority
    }

    /// Runs one synchronous mutation only if `expectedAuthority` is still current.
    /// Validation and mutation occur while the same lock is held, so an authority
    /// transition cannot interleave between the check and irreversible recorder
    /// mutation.
    func withCurrentAuthority<Result>(
        _ expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        operation: () throws -> Result
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        guard currentAuthority == expectedAuthority else {
            throw StateError.authorityChanged
        }
        return try operation()
    }
}

extension PassiveCoreBluetoothCaptureRecorder {
    /// Recorder-actor mutation path that rejects a stale decision at the actual
    /// mutation point rather than relying on a post-await MainActor recheck.
    ///
    /// The gate closure is synchronous. `recordObservationBoundary` below is an
    /// actor-isolated synchronous mutation once this actor has been entered, so no
    /// suspension point exists between authority validation and session append.
    func recordObservationBoundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        observedAtUptimeNanoseconds: UInt64,
        observedAtDate: Date,
        authority: PassiveCoreBluetoothArtifactAuthorityContext,
        mutationGate: PassiveCoreBluetoothArtifactAuthorityMutationGate
    ) throws {
        try mutationGate.withCurrentAuthority(authority) {
            try recordObservationBoundary(
                kind,
                observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
                observedAtDate: observedAtDate
            )
        }
    }
}

extension PassiveCoreBluetoothObservationBoundaryDecision {
    /// Carries this exact pre-await decision through the actor hop and revalidates
    /// its authority at the recorder's irreversible mutation point.
    func recordBoundary(
        on recorder: PassiveCoreBluetoothCaptureRecorder,
        mutationGate: PassiveCoreBluetoothArtifactAuthorityMutationGate
    ) async throws {
        try await recorder.recordObservationBoundary(
            observationBoundaryKind,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            observedAtDate: observedAtDate,
            authority: authority,
            mutationGate: mutationGate
        )
    }
}
