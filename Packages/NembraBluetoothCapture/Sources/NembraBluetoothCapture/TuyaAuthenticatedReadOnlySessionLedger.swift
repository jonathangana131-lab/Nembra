import Dispatch
import Foundation

/// Process-local connection identity minted by the read-only Tuya session ledger.
/// Callers may retain a token for callback attribution, but cannot construct a token for a
/// different ledger instance or connection generation.
public struct TuyaReadOnlyConnectionToken: Hashable, Sendable {
    fileprivate let ledgerID: UUID
    fileprivate let generation: UInt64

    public var diagnosticGeneration: UInt64 { generation }

    fileprivate init(ledgerID: UUID, generation: UInt64) {
        self.ledgerID = ledgerID
        self.generation = generation
    }
}

/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.
///
/// The official Tuya adapter reports lifecycle events here rather than assembling preflight
/// snapshots itself. The ledger samples monotonic uptime at the mutation boundary, resets
/// authentication/application evidence on every new connection, rejects callbacks attributed to
/// an older connection token or a different ledger instance, and retires callback authority at
/// terminal acceptance/failure horizons. Structured SDK values and raw transport bytes do not
/// cross this boundary; callers report only whether an application update was non-empty.
public actor TuyaAuthenticatedReadOnlySessionLedger: TuyaReadOnlyAuthenticationSessionProvider {
    /// Maximum unobserved interval accepted inside one continuous authenticated observation.
    /// The app polls current SDK-local BLE state more frequently than this; a suspension or
    /// scheduling gap beyond this horizon cannot be erased by a queued application callback.
    public static let maximumContinuousObservationGapNanoseconds: UInt64 = 5_000_000_000

    public enum MutationError: Error, Equatable, Sendable {
        case noActiveConnection
        case staleConnection
        case invalidAuthenticationTransition
        case authenticationRequired
        case emptyApplicationUpdate
        case applicationPayloadCountExhausted
        case monotonicClockRegressed
        case connectionGenerationExhausted
        case observationContinuityInvalidated
        case preflightNotReady
    }

    private static let observationContinuityFailureReason =
        "Authenticated observation continuity was invalidated by a long observation gap."

    private let ledgerID: UUID
    private let nowUptimeNanoseconds: @Sendable () -> UInt64

    private var generation: UInt64 = 0
    private var currentToken: TuyaReadOnlyConnectionToken?
    private var authenticationState: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState =
        .unavailable(reason: "No active Bluetooth connection.")
    private var authenticationMethod: TuyaReadOnlyAuthenticationMethod?
    private var connectionStartedAtUptimeNanoseconds: UInt64?
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var latestObservedUptimeNanoseconds: UInt64?
    private var applicationPayloadCount = 0
    private var latestApplicationPayloadUptimeNanoseconds: UInt64?

    public init() {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds }
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
    }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else {
            throw MutationError.connectionGenerationExhausted
        }

        generation += 1
        let token = TuyaReadOnlyConnectionToken(ledgerID: ledgerID, generation: generation)
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
        guard case .waitingForAuthentication = authenticationState else {
            throw MutationError.invalidAuthenticationTransition
        }
        let now = try nextMonotonicObservation()
        authenticationState = .authenticating
        latestObservedUptimeNanoseconds = now
    }

    public func markAuthenticated(
        for token: TuyaReadOnlyConnectionToken,
        method: TuyaReadOnlyAuthenticationMethod
    ) throws {
        try requireCurrent(token)
        // Current V14 authority requires an explicit authentication-start event in the same
        // generation. A success callback cannot jump from a freshly minted connection directly
        // into authenticated state merely by carrying an accepted method label.
        guard case .authenticating = authenticationState else {
            throw MutationError.invalidAuthenticationTransition
        }

        let now = try nextMonotonicObservation()
        authenticationState = .authenticated
        authenticationMethod = method
        authenticatedAtUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    /// Retires current session authority when the official SDK reports a terminal failure.
    ///
    /// If failure occurs while authentication is in progress, no authentication provenance exists
    /// and pre-auth fields remain empty. If the SDK reports a terminal failure after an
    /// authenticated session was already observed, earned chronology is retained for diagnostics
    /// while `.failed` and token retirement make it permanently non-authorizing.
    public func markAuthenticationFailed(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        switch authenticationState {
        case .authenticating:
            authenticationMethod = nil
            authenticatedAtUptimeNanoseconds = nil
            applicationPayloadCount = 0
            latestApplicationPayloadUptimeNanoseconds = nil
        case .authenticated:
            break
        case .waitingForAuthentication, .unavailable, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        let now = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Tuya SDK session failed.")
        latestObservedUptimeNanoseconds = now
        currentToken = nil
    }

    /// Records only the presence and receipt time of a non-empty application-level update.
    ///
    /// This deliberately accepts no `Data`: the current SmartLife SDK surface provides a
    /// structured `dpsUpdate` dictionary, not byte-exact FD50 transport. Callers must not invent
    /// serialized bytes merely to satisfy this chronology gate.
    ///
    /// Continuity is checked before the update may advance `latestObserved...`. This closes the
    /// resume-order race where a queued SDK update could otherwise erase a long suspension gap
    /// before the app watchdog observes it.
    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }

        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        guard let authenticatedAt = authenticatedAtUptimeNanoseconds,
              now >= authenticatedAt else {
            throw MutationError.monotonicClockRegressed
        }
        guard applicationPayloadCount < Int.max else {
            throw MutationError.applicationPayloadCountExhausted
        }
        applicationPayloadCount += 1
        latestApplicationPayloadUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
    }

    /// Advances only the non-secret liveness observation for the current authenticated connection.
    /// No telemetry or application payload is manufactured by this call.
    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        latestObservedUptimeNanoseconds = now
    }

    /// Seals a failed observation horizon while authenticated transport may still exist.
    ///
    /// A suspended/stalled observation loop proves that Nembra can no longer claim continuous
    /// witnessed liveness, but it does not prove the SDK BLE transport disconnected. Earned
    /// authentication/application chronology remains diagnostic while callback authority retires.
    public func markObservationContinuityInvalidated(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Authenticated observation continuity was interrupted.")
        currentToken = nil
    }

    /// Seals a post-authentication attempt that remained connected but failed to produce the
    /// required application evidence. This is deliberately distinct from `endConnection`: the
    /// terminal fact is "authenticated observation failed", not "Bluetooth disconnected".
    public func markApplicationObservationTimedOut(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        let now = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Authenticated session produced no application update before the observation deadline.")
        latestObservedUptimeNanoseconds = now
        currentToken = nil
    }

    /// Freezes an already-earned canonical ready verdict without manufacturing a later receipt or
    /// extending its duration. Retiring the token makes the accepted prefix immutable: delayed
    /// callbacks from this connection can no longer mutate update count or liveness chronology.
    public func sealAcceptedObservation(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        let snapshot = makeSnapshot()
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        currentToken = nil
    }

    public func endConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        let now = try nextMonotonicObservation()
        currentToken = nil
        authenticationState = .unavailable(reason: "Bluetooth connection ended.")
        authenticationMethod = nil
        connectionStartedAtUptimeNanoseconds = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    public func currentPreflightSnapshot() async -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
        makeSnapshot()
    }

    private func makeSnapshot() -> TuyaAuthenticatedReadOnlyPreflightSnapshot {
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

    private func requireCurrent(_ token: TuyaReadOnlyConnectionToken) throws {
        guard let currentToken else {
            throw MutationError.noActiveConnection
        }
        guard currentToken == token else {
            throw MutationError.staleConnection
        }
    }

    private func nextMonotonicObservation() throws -> UInt64 {
        let now = nowUptimeNanoseconds()
        if let latestObservedUptimeNanoseconds,
           now < latestObservedUptimeNanoseconds {
            throw MutationError.monotonicClockRegressed
        }
        return now
    }

    /// Must run before any authenticated mutation can move the accepted observation horizon.
    /// On failure, preserve the last legitimate timestamps/evidence and retire callback authority.
    private func requireContinuousAuthenticatedObservation(at now: UInt64) throws {
        guard let latest = latestObservedUptimeNanoseconds,
              now >= latest else {
            throw MutationError.monotonicClockRegressed
        }
        guard now - latest <= Self.maximumContinuousObservationGapNanoseconds else {
            authenticationState = .failed(reason: Self.observationContinuityFailureReason)
            currentToken = nil
            throw MutationError.observationContinuityInvalidated
        }
    }
}
