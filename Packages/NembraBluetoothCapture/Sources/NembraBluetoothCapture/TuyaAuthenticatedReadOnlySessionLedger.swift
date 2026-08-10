import Dispatch
import Foundation

public struct TuyaReadOnlyConnectionToken: Hashable, Sendable {
    fileprivate let ledgerID: UUID
    fileprivate let generation: UInt64
    public var diagnosticGeneration: UInt64 { generation }
    fileprivate init(ledgerID: UUID, generation: UInt64) {
        self.ledgerID = ledgerID
        self.generation = generation
    }
}

/// Canonical non-secret chronology for the authenticated read-only Tuya session.
/// Every chronology-advancing authenticated mutation enforces the same continuity horizon before
/// it may move the observation clock. This prevents a queued SDK application callback from erasing
/// an app-suspension/polling gap before a watchdog observes it.
public actor TuyaAuthenticatedReadOnlySessionLedger: TuyaReadOnlyAuthenticationSessionProvider {
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
        case preflightNotReady
        case observationContinuityInvalidated
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
        ledgerID = UUID()
        nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds }
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        ledgerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
    }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else { throw MutationError.connectionGenerationExhausted }
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
        switch authenticationState {
        case .waitingForAuthentication, .authenticating: break
        case .unavailable, .authenticated, .failed:
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

    /// Terminal SDK failure revokes current authority while preserving already-earned authenticated
    /// chronology as non-authorizing diagnostics when failure arrives after an observed session.
    public func markAuthenticationFailed(for token: TuyaReadOnlyConnectionToken) throws {
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
        let now = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Tuya SDK session failed.")
        latestObservedUptimeNanoseconds = now
        currentToken = nil
    }

    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else { throw MutationError.authenticationRequired }
        guard isNonEmpty else { throw MutationError.emptyApplicationUpdate }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        guard let authenticatedAt = authenticatedAtUptimeNanoseconds, now >= authenticatedAt else {
            throw MutationError.monotonicClockRegressed
        }
        guard applicationPayloadCount < Int.max else { throw MutationError.applicationPayloadCountExhausted }
        applicationPayloadCount += 1
        latestApplicationPayloadUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
    }

    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else { throw MutationError.authenticationRequired }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        latestObservedUptimeNanoseconds = now
    }

    public func markApplicationObservationTimedOut(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else { throw MutationError.authenticationRequired }
        let now = try nextMonotonicObservation()
        authenticationState = .failed(
            reason: "Authenticated session produced no application update before the observation deadline."
        )
        latestObservedUptimeNanoseconds = now
        currentToken = nil
    }

    public func sealAcceptedObservation(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: makeSnapshot()) == .readyForStationaryMapping else {
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
        guard let currentToken else { throw MutationError.noActiveConnection }
        guard currentToken == token else { throw MutationError.staleConnection }
    }

    private func nextMonotonicObservation() throws -> UInt64 {
        let now = nowUptimeNanoseconds()
        if let latestObservedUptimeNanoseconds, now < latestObservedUptimeNanoseconds {
            throw MutationError.monotonicClockRegressed
        }
        return now
    }

    /// Called before any authenticated mutation can move the observation horizon. On a long gap,
    /// preserve every already-legitimate receipt/timestamp for diagnostics, mark the attempt failed,
    /// and retire the owner token before the queued callback can refresh chronology.
    private func requireContinuousAuthenticatedObservation(at now: UInt64) throws {
        guard let latest = latestObservedUptimeNanoseconds, now >= latest else {
            throw MutationError.monotonicClockRegressed
        }
        guard now - latest <= Self.maximumContinuousObservationGapNanoseconds else {
            authenticationState = .failed(reason: Self.observationContinuityFailureReason)
            currentToken = nil
            throw MutationError.observationContinuityInvalidated
        }
    }
}
