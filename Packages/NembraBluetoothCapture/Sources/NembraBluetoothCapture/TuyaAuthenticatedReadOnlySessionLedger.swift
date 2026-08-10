import Dispatch
import Foundation

/// Opaque process-local identity for one authenticated-session candidate.
///
/// App code may retain this token to attribute asynchronous SDK callbacks, but cannot mint a
/// token for another generation or change its generation value.
public struct TuyaReadOnlyConnectionToken: Hashable, Sendable {
    fileprivate let generation: UInt64

    public var diagnosticGeneration: UInt64 { generation }

    fileprivate init(generation: UInt64) {
        self.generation = generation
    }
}

/// Package-owned chronology ledger for the read-only Tuya physical preflight.
///
/// The official SDK adapter reports lifecycle observations here. The ledger mints connection
/// generations, samples monotonic uptime at the mutation boundary, rejects stale callbacks, and
/// produces the only production snapshots consumed by `TuyaAuthenticatedReadOnlyPreflight`.
///
/// This type stores no Tuya account identifier, verification code, AppKey/AppSecret, local key,
/// session key, DP value, or raw FD50 bytes. A genuine structured SDK `dpsUpdate` is represented
/// only by its non-zero field count and receipt time; the diagnostic/export layer may separately
/// preserve a sanitized string projection without claiming byte-exact transport evidence.
public actor TuyaAuthenticatedReadOnlySessionLedger: TuyaReadOnlyAuthenticationSessionProvider {
    public enum MutationError: Error, Equatable, Sendable {
        case noActiveConnection
        case staleConnection
        case invalidAuthenticationTransition
        case authenticationRequired
        case emptyApplicationObservation
        case applicationPayloadCountExhausted
        case monotonicClockRegressed
        case connectionGenerationExhausted
    }

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
        nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds }
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
    }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else {
            throw MutationError.connectionGenerationExhausted
        }

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
        case .waitingForAuthentication, .authenticating:
            break
        case .unavailable, .authenticated, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        let now = try nextMonotonicObservation()
        authenticationState = .authenticated
        authenticationMethod = method
        authenticatedAtUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
        // Pre-auth callbacks cannot satisfy the accepted application-data gate.
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    /// Admit one genuine non-empty application-level SDK observation for the current generation.
    ///
    /// `fieldCount` is the number of fields in the already-observed SDK application callback. It
    /// is used only to reject an empty callback; no DP key/value or raw transport byte is retained.
    public func recordApplicationObservation(
        fieldCount: Int,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard fieldCount > 0 else {
            throw MutationError.emptyApplicationObservation
        }

        let now = try nextMonotonicObservation()
        guard let authenticatedAtUptimeNanoseconds,
              now >= authenticatedAtUptimeNanoseconds else {
            throw MutationError.monotonicClockRegressed
        }
        guard applicationPayloadCount < Int.max else {
            throw MutationError.applicationPayloadCountExhausted
        }

        applicationPayloadCount += 1
        latestApplicationPayloadUptimeNanoseconds = now
        latestObservedUptimeNanoseconds = now
    }

    /// Record that the official session is still current at this monotonic observation.
    /// This does not manufacture an application payload or any telemetry value.
    public func observeCurrentAuthenticatedConnection(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        latestObservedUptimeNanoseconds = try nextMonotonicObservation()
    }

    public func markAuthenticationFailed(
        for token: TuyaReadOnlyConnectionToken,
        reason: String = "Tuya authentication failed."
    ) throws {
        try requireCurrent(token)
        switch authenticationState {
        case .waitingForAuthentication, .authenticating, .authenticated:
            break
        case .unavailable, .failed:
            throw MutationError.invalidAuthenticationTransition
        }

        let now = try nextMonotonicObservation()
        authenticationState = .failed(reason: reason)
        authenticationMethod = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    public func endConnection(
        for token: TuyaReadOnlyConnectionToken,
        reason: String = "Bluetooth connection ended."
    ) throws {
        try requireCurrent(token)
        let now = try nextMonotonicObservation()

        currentToken = nil
        authenticationState = .unavailable(reason: reason)
        authenticationMethod = nil
        connectionStartedAtUptimeNanoseconds = nil
        authenticatedAtUptimeNanoseconds = nil
        latestObservedUptimeNanoseconds = now
        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
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
}
