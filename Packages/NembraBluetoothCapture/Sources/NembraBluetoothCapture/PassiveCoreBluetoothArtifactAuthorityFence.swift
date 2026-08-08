import Foundation

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
/// The caller that owns artifact authority must transition this fence in the same
/// synchronous operation that advances its own authority. A recorder-side mutation
/// then calls `withCurrentAuthority(_:_:)`; the authority check and supplied
/// mutation execute while this fence holds one non-async critical section.
/// Therefore either the mutation wins before the authority transition, or the
/// authority transition wins and the stale mutation is rejected before its body
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
    }

    private let lock = NSLock()
    private var currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext

    init(authority: PassiveCoreBluetoothArtifactAuthorityContext) {
        currentAuthority = authority
    }

    /// Executes `mutation` only if `expectedAuthority` is still exactly current.
    ///
    /// The equality check and the complete synchronous mutation body share the same
    /// lock hold. An authority transition cannot interleave between them.
    func withCurrentAuthority<Result>(
        _ expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        _ mutation: () throws -> Result
    ) throws -> Result {
        try synchronized {
            guard currentAuthority == expectedAuthority else {
                throw StateError.authorityChanged(
                    expected: expectedAuthority,
                    current: currentAuthority
                )
            }
            return try mutation()
        }
    }

    /// Atomically replaces the current authority only when the caller still owns
    /// the exact expected authority. A delayed/stale transition cannot rewind or
    /// overwrite a newer authority.
    func transition(
        from expectedAuthority: PassiveCoreBluetoothArtifactAuthorityContext,
        to newAuthority: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        try synchronized {
            guard currentAuthority == expectedAuthority else {
                throw StateError.authorityChanged(
                    expected: expectedAuthority,
                    current: currentAuthority
                )
            }
            currentAuthority = newAuthority
        }
    }

    private func synchronized<Result>(
        _ body: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
