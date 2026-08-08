import Foundation

/// Synchronously linearizes artifact-authority changes with authority-sensitive
/// recorder mutations.
///
/// MainActor checks around an actor hop are insufficient: authority can change
/// while the caller is suspended and a stale recorder mutation can otherwise land
/// before the post-await check notices the change. This fence moves the final
/// authority check to the mutation point itself.
///
/// The lock is never held across `await`. A boundary append executes entirely
/// inside `withValidatedAuthority`, so either the append linearizes before an
/// authority replacement or the stale append fails before mutating evidence.
///
/// `@unchecked Sendable` is justified because the only mutable state is protected
/// by `lock`, and the contained authority context is `Sendable`.
final class PassiveCoreBluetoothArtifactAuthorityMutationFence: @unchecked Sendable {
    enum StateError: Error, Equatable, Sendable {
        case authorityChanged
    }

    private let lock = NSLock()
    private var authority: PassiveCoreBluetoothArtifactAuthorityContext

    init(initialAuthority: PassiveCoreBluetoothArtifactAuthorityContext) {
        authority = initialAuthority
    }

    var currentAuthority: PassiveCoreBluetoothArtifactAuthorityContext {
        lock.lock()
        defer { lock.unlock() }
        return authority
    }

    /// Replaces authority only if the caller still owns the exact authority it
    /// intends to retire. Live controller authority changes belong to MainActor;
    /// the lock exists so recorder-actor mutation can linearize against that
    /// synchronous replacement, not to create a second authority owner.
    @MainActor
    func replace(
        expectedCurrent: PassiveCoreBluetoothArtifactAuthorityContext,
        with replacement: PassiveCoreBluetoothArtifactAuthorityContext
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard authority == expectedCurrent else {
            throw StateError.authorityChanged
        }
        authority = replacement
    }

    /// Executes one synchronous mutation only while `expected` is still the
    /// fence's exact current authority. The operation must not suspend.
    func withValidatedAuthority<Result>(
        _ expected: PassiveCoreBluetoothArtifactAuthorityContext,
        _ operation: () throws -> Result
    ) throws -> Result {
        lock.lock()
        defer { lock.unlock() }

        guard authority == expected else {
            throw StateError.authorityChanged
        }
        return try operation()
    }
}
