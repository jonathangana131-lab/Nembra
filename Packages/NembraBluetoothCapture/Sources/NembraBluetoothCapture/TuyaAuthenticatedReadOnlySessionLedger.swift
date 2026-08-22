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
        case incompleteObservationHorizonReached
        case preflightNotReady
    }

    private static let observationContinuityFailureReason =
        "Authenticated observation continuity was invalidated by a long observation gap."
    private static let sourceAuthorityFailureReason =
        "Tuya SDK source authority was invalidated."
    private static let internalLifecycleFailureReason =
        "Session authority was retired after an internal lifecycle or chronology failure."

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

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Tuya SDK session failed.")
        currentToken = nil
    }

    public func markInternalLifecycleFailure(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)

        switch authenticationState {
        case .waitingForAuthentication, .authenticating:
            authenticationMethod = nil
            authenticatedAtUptimeNanoseconds = nil
            applicationPayloadCount = 0
            latestApplicationPayloadUptimeNanoseconds = nil
        case .authenticated:
            break
        case .unavailable, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        authenticationState = .failed(reason: Self.internalLifecycleFailureReason)
        currentToken = nil
    }

    public func markSourceAuthorityInvalidated(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)

        switch authenticationState {
        case .waitingForAuthentication, .authenticating:
            authenticationMethod = nil
            authenticatedAtUptimeNanoseconds = nil
            applicationPayloadCount = 0
            latestApplicationPayloadUptimeNanoseconds = nil
        case .authenticated:
            break
        case .unavailable, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.sourceAuthorityFailureReason)
        currentToken = nil
    }

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

        let preMutationHorizonSnapshot = TuyaAuthenticatedReadOnlyPreflightSnapshot(
            authenticationState: authenticationState,
            authenticationMethod: authenticationMethod,
            connectionStartedAtUptimeNanoseconds: connectionStartedAtUptimeNanoseconds,
            authenticatedAtUptimeNanoseconds: authenticatedAtUptimeNanoseconds,
            latestObservedUptimeNanoseconds: now,
            applicationPayloadCount: applicationPayloadCount,
            latestApplicationPayloadUptimeNanoseconds: latestApplicationPayloadUptimeNanoseconds,
            connectionGeneration: currentToken?.generation ?? generation
        )
        if TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(preMutationHorizonSnapshot) {
            throw MutationError.incompleteObservationHorizonReached
        }

        guard applicationPayloadCount < Int.max else {
            throw MutationError.applicationPayloadCountExhausted
        }
        applicationPayloadCount += 1
        latestApplicationPayloadUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
    }

    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        latestObservedUptimeNanoseconds = now

        if TuyaAuthenticatedReadOnlyPreflight.shouldRetireIncompleteObservation(makeSnapshot()) {
            throw MutationError.incompleteObservationHorizonReached
        }
    }

    public func markObservationContinuityInvalidated(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.observationContinuityFailureReason)
        currentToken = nil
    }

    public func markApplicationObservationTimedOut(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Authenticated session produced no application update before the observation deadline.")
        currentToken = nil
    }

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
