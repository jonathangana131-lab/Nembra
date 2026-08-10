import Dispatch
import Foundation

/// Process-local connection identity minted by the read-only Tuya session ledger.
/// Callers may retain a token for callback attribution, but cannot construct a token for a
/// different connection generation.
public struct TuyaReadOnlyConnectionToken: Hashable, Sendable {
    fileprivate let generation: UInt64
    public var diagnosticGeneration: UInt64 { generation }
    fileprivate init(generation: UInt64) { self.generation = generation }
}

/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.
///
/// The official Tuya adapter reports lifecycle events here rather than assembling preflight
/// snapshots itself. The ledger samples monotonic uptime at each mutation, resets authority on
/// every new connection, and rejects callbacks attributed to an older or terminal attempt.
/// Application evidence is admitted from a non-empty decoded SDK update; this type never asks
/// the adapter to manufacture raw FD50 bytes and retains neither DP values nor credentials.
public actor TuyaAuthenticatedReadOnlySessionLedger: TuyaReadOnlyAuthenticationSessionProvider {
    public enum MutationError: Error, Equatable, Sendable {
        case noActiveConnection
        case staleConnection
        case invalidAuthenticationTransition
        case authenticationRequired
        case emptyApplicationUpdate
        case applicationPayloadCountExhausted
        case monotonicClockRegressed
        case connectionGenerationExhausted
    }

    private let nowUptimeNanoseconds: @Sendable () -> UInt64
    private var generation: UInt64 = 0
    private var currentToken: TuyaReadOnlyConnectionToken?
    private var authenticationState: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState = .unavailable(reason: "No active Bluetooth connection.")
    private var authenticationMethod: TuyaReadOnlyAuthenticationMethod?
    private var connectionStartedAtUptimeNanoseconds: UInt64?
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var latestObservedUptimeNanoseconds: UInt64?
    private var applicationPayloadCount = 0
    private var latestApplicationPayloadUptimeNanoseconds: UInt64?

    public init() { self.nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds } }
    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) { self.nowUptimeNanoseconds = nowUptimeNanoseconds }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else { throw MutationError.connectionGenerationExhausted }
        generation += 1
        let token = TuyaReadOnlyConnectionToken(generation: generation)
        let now = nowUptimeNanoseconds()
        currentToken = token
        authenticationState = .waitingForAuthentication
        authenticationMethod = nil
        connectionStartedAtUptimeNanoseconds = now
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
        return token
    }

    public func markAuthenticationStarted(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .waitingForAuthentication = authenticationState else { throw MutationError.invalidAuthenticationTransition }
        let now = try nextMonotonicObservation()
        authenticationState = .authenticating
        latestObservedUptimeNanoseconds = now
    }

    public func markAuthenticated(for token: TuyaReadOnlyConnectionToken, method: TuyaReadOnlyAuthenticationMethod) throws {
        try requireCurrent(token)
        switch authenticationState {
        case .waitingForAuthentication, .authenticating: break
        case .unavailable, .authenticated, .failed: throw MutationError.invalidAuthenticationTransition
        }
        let now = try nextMonotonicObservation()
        authenticationState = .authenticated
        authenticationMethod = method
        authenticatedAtUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    public func markAuthenticationFailed(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        switch authenticationState {
        case .waitingForAuthentication, .authenticating: break
        case .unavailable, .authenticated, .failed: throw MutationError.invalidAuthenticationTransition
        }
        try retireCurrentAttempt(state: .failed(reason: "Tuya authentication failed."))
    }

    /// Admits one genuine non-empty decoded SDK application/DP update for this authenticated
    /// connection generation. `fieldCount` describes the SDK callback only; it is not raw bytes,
    /// a DP semantic claim, or telemetry evidence.
    public func recordApplicationUpdate(fieldCount: Int, for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else { throw MutationError.authenticationRequired }
        guard fieldCount > 0 else { throw MutationError.emptyApplicationUpdate }
        let now = try nextMonotonicObservation()
        guard let authenticatedAt = authenticatedAtUptimeNanoseconds, now >= authenticatedAt else { throw MutationError.monotonicClockRegressed }
        guard applicationPayloadCount < Int.max else { throw MutationError.applicationPayloadCountExhausted }
        applicationPayloadCount += 1
        latestApplicationPayloadUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
    }

    /// Advances only non-secret liveness for the current connection. No application data is
    /// manufactured by this call.
    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        latestObservedUptimeNanoseconds = try nextMonotonicObservation()
    }

    /// Permanently retires a failed observation attempt even if the underlying SDK transport
    /// emits a late callback. This is distinct from claiming that Bluetooth physically ended.
    public func invalidateAttempt(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        try retireCurrentAttempt(state: .failed(reason: "Authenticated read-only attempt invalidated."))
    }

    public func endConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        try retireCurrentAttempt(state: .unavailable(reason: "Bluetooth connection ended."), clearConnectionStart: true)
    }

    public func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: authenticationState,
            authenticationMethod: authenticationMethod,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: latestObservedUptimeNanoseconds,
            applicationPayloadCount: applicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadUptimeNanoseconds,
            connectionGeneration: currentToken?.generation ?? generation
        )
    }

    private func retireCurrentAttempt(state: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState, clearConnectionStart: Bool = false) throws {
        let now = try nextMonotonicObservation()
        currentToken = nil
        authenticationState = state
        authenticationMethod = nil
        if clearConnectionStart { connectionStartedAtUptimeNanoseconds = nil }
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    private func requireCurrent(_ token: TuyaReadOnlyConnectionToken) throws {
        guard let currentToken else { throw MutationError.noActiveConnection }
        guard currentToken == token else { throw MutationError.staleConnection }
    }

    private func nextMonotonicObservation() throws -> UInt64 {
        let now = nowUptimeNanoseconds()
        if let latestObservedUptimeNanoseconds, now < latestObservedUptimeNanoseconds { throw MutationError.monotonicClockRegressed }
        return now
    }
}
