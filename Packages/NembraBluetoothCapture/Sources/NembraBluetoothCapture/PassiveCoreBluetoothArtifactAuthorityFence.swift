import Foundation
import NembraCore

/// Synchronously serializes one mutable capture-artifact authority with mutations
/// that are only valid while an exact authority remains current.
///
/// This closes a different boundary from ordinary queued-event provenance. Raw
/// callback evidence may legitimately drain after the controller has advanced to a
/// later authority because each callback already owns its recorder/session identity.
/// An observation-boundary append is different: it is an irreversible grammar
/// mutation and must not begin after the authority that admitted it has been
/// revoked.
///
/// The MainActor owner that advances artifact authority must transition this fence
/// in the same synchronous operation that advances its own mirrored authority. The
/// fence transition must happen **before** publishing the new owner value. Otherwise
/// a concurrent recorder executor could observe the owner at B while this fence still
/// admits stale A for a brief window. After the fence transition returns, publishing
/// the already-computed B value is non-failable and requires no actor suspension.
///
/// A recorder-side mutation calls `withCurrentAuthority(_:_:)`; the authority check
/// and supplied mutation execute while this fence holds one non-async critical
/// section. Therefore either the mutation wins before the authority transition, or
/// the authority transition wins and the stale mutation is rejected before its body
/// executes.
///
/// The mutation closure is intentionally synchronous and nonescaping. It must not
/// perform asynchronous work or re-enter this fence. The unchecked Sendable
/// conformance is safe because all mutable state is protected by `lock`.
///
/// This is process-local software evidence authority only. It establishes no BLE/RF
/// completeness, physical scooter identity, protocol semantics, or command authority.
final class PassiveCoreBluetoothArtifactAuthorityFence: @unchecked Sendable {
    enum StateError: Error, Equatable, Sendable {
        case authorityChanged(
            expected: PassiveCoreBluetoothArtifactAuthorityContext,
            current: PassiveCoreBluetoothArtifactAuthorityContext
        )
        case nonAdvancingTransition(
            from: PassiveCoreBluetoothArtifactAuthorityContext,
            to: PassiveCoreBluetoothArtifactAuthorityContext
        )
    }

    private let lock = NSLock()
    private var storedAuthority: PassiveCoreBluetoothArtifactAuthorityContext

    init(authority: PassiveCoreBluetoothArtifactAuthorityContext) {
        storedAuthority = authority
    }

    /// Read-only authority projection for synchronous MainActor admissions. Keeping
    /// sampling on the same actor as `transition(from:to:)` means a decision can
    /// capture this value and begin its queue transaction without an authority
    /// replacement interleaving that synchronous admission.
    @MainActor
    var currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext {
        synchronized { storedAuthority }
    }

    /// Executes `mutation` only if `expectedAuthority` is still exactly current.
    ///
    /// This method intentionally remains callable from the recorder actor. The
    /// equality check and the complete synchronous mutation body share the same lock
    /// hold, so the MainActor authority transition cannot interleave between them.
    func withCurrentAuthority<Result>(
        _ expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        _ mutation: () throws -> Result
    ) throws -> Result {
        try synchronized {
            guard storedAuthority == expectedAuthority else {
                throw StateError.authorityChanged(
                    expected: expectedAuthority,
                    current: storedAuthority
                )
            }
            return try mutation()
        }
    }

    /// Atomically replaces the current authority only when the MainActor caller
    /// still owns the exact expected authority and the full authority context moves
    /// strictly forward.
    ///
    /// Ordering is lexicographic by durable target session first, then authority
    /// generation within that session:
    /// - a newer target-session generation may begin with its own authority counter;
    /// - within one target session, authority generation must strictly increase;
    /// - same, older-session, and same-session backward transitions fail closed.
    ///
    /// This prevents a retired full-context token from becoming current again while
    /// avoiding a false requirement that a fresh durable session inherit the old
    /// session's authority counter forever.
    ///
    /// If another MainActor owner variable mirrors this authority, call this method
    /// before assigning that variable its new value. No asynchronous suspension
    /// belongs between the fence transition and owner publication.
    @MainActor
    func transition(
        from expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        to newAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        try synchronized {
            guard storedAuthority == expectedAuthority else {
                throw StateError.authorityChanged(
                    expected: expectedAuthority,
                    current: storedAuthority
                )
            }
            guard Self.isStrictlyNewer(newAuthority, than: expectedAuthority) else {
                throw StateError.nonAdvancingTransition(
                    from: expectedAuthority,
                    to: newAuthority
                )
            }
            storedAuthority = newAuthority
        }
    }

    private static func isStrictlyNewer(
        _ candidate: PassiveCoreBluetoothArtifactAuthorityContext,
        than current: PassiveCoreBluetoothArtifactAuthorityContext
    ) -> Bool {
        if candidate.targetSessionGeneration > current.targetSessionGeneration {
            return true
        }
        guard candidate.targetSessionGeneration == current.targetSessionGeneration else {
            return false
        }
        return candidate.authorityGeneration > current.authorityGeneration
    }

    private func synchronized<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

extension PassiveCoreBluetoothCaptureRecorder {
    /// Authority-sensitive explicit-clock lifecycle mutation.
    ///
    /// The actor hop happens before this synchronous method begins. Once on the
    /// recorder actor, the exact authority check and the existing synchronous
    /// boundary append share one fence hold. If authority changed while the caller
    /// was suspended waiting for this actor, the stale decision appends zero
    /// observation-boundary evidence.
    func recordObservationBoundary(
        _ kind: PassiveBluetoothObservationBoundaryKind,
        observedAtUptimeNanoseconds: UInt64,
        observedAtDate: Date,
        expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
    ) throws {
        try authorityFence.withCurrentAuthority(expectedAuthority) {
            try recordObservationBoundary(
                kind,
                observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
                observedAtDate: observedAtDate
            )
        }
    }
}

extension PassiveCoreBluetoothObservationBoundaryDecision {
    /// Carries the exact pre-await #411 decision clocks and authority through the
    /// recorder actor hop to the irreversible mutation point.
    func recordBoundary(
        on recorder: PassiveCoreBluetoothCaptureRecorder,
        authorityFence: PassiveCoreBluetoothArtifactAuthorityFence
    ) async throws {
        try await recorder.recordObservationBoundary(
            observationBoundaryKind,
            observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
            observedAtDate: observedAtDate,
            expectedAuthority: authority,
            authorityFence: authorityFence
        )
    }
}
