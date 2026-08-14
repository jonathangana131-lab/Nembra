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

/// Opaque application-delivery chronology issued by one exact ledger instance.
///
/// The shipping caller can retain this value long enough to cross an async admission hop, but it
/// cannot construct one, read/rewrite its timestamp, choose the issuer, or choose the delivery ID.
public struct TuyaReadOnlyApplicationReceipt: Sendable {
    fileprivate let token: TuyaReadOnlyConnectionToken
    fileprivate let issuerID: UUID
    fileprivate let deliveryID: UUID
    fileprivate let receivedAtUptimeNanoseconds: UInt64

    fileprivate init(
        token: TuyaReadOnlyConnectionToken,
        issuerID: UUID,
        deliveryID: UUID,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        self.token = token
        self.issuerID = issuerID
        self.deliveryID = deliveryID
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
}

/// Synchronous arbitration between SDK callback delivery and watchdog liveness sampling.
///
/// Both paths sample the same ledger clock while holding this lock. If callback delivery wins, its
/// receipt is registered pending before a queued watchdog can sample later liveness. If liveness
/// wins, its sample necessarily precedes the subsequently issued receipt. Actor mutation still owns
/// all accepted evidence; this object only establishes scheduler-independent ordering.
private final class TuyaReadOnlyApplicationDeliveryArbiter: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingByDeliveryID: [UUID: TuyaReadOnlyConnectionToken] = [:]

    func capture(
        for token: TuyaReadOnlyConnectionToken,
        issuerID: UUID,
        nowUptimeNanoseconds: @Sendable () -> UInt64
    ) -> TuyaReadOnlyApplicationReceipt {
        lock.lock()
        defer { lock.unlock() }

        let deliveryID = UUID()
        let receipt = TuyaReadOnlyApplicationReceipt(
            token: token,
            issuerID: issuerID,
            deliveryID: deliveryID,
            receivedAtUptimeNanoseconds: nowUptimeNanoseconds()
        )
        pendingByDeliveryID[deliveryID] = token
        return receipt
    }

    func consume(_ receipt: TuyaReadOnlyApplicationReceipt) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard pendingByDeliveryID[receipt.deliveryID] == receipt.token else {
            return false
        }
        pendingByDeliveryID.removeValue(forKey: receipt.deliveryID)
        return true
    }

    func livenessSampleIfUnblocked(
        for token: TuyaReadOnlyConnectionToken,
        nowUptimeNanoseconds: @Sendable () -> UInt64
    ) -> UInt64? {
        lock.lock()
        defer { lock.unlock() }

        guard !pendingByDeliveryID.values.contains(token) else {
            return nil
        }
        return nowUptimeNanoseconds()
    }

    func reset() {
        lock.lock()
        pendingByDeliveryID.removeAll(keepingCapacity: true)
        lock.unlock()
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
        case invalidApplicationReceipt
        case applicationDeliveryReceiptAlreadyConsumed
        case applicationPayloadCountExhausted
        case monotonicClockRegressed
        case connectionGenerationExhausted
        case observationContinuityInvalidated
        case incompleteObservationHorizonReached
        case preflightNotReady
    }

    private static let observationContinuityFailureReason =
        "Authenticated observation continuity was invalidated by a long observation gap."
    private static let incompleteObservationFailureReason =
        "Authenticated session ended because required repeated application evidence did not become sufficient before the observation deadline."
    private static let sourceAuthorityFailureReason =
        "Tuya SDK source authority was invalidated."
    private static let internalLifecycleFailureReason =
        "Session authority was retired after an internal lifecycle or chronology failure."

    private let ledgerID: UUID
    nonisolated private let applicationReceiptIssuerID: UUID
    nonisolated private let applicationDeliveryArbiter: TuyaReadOnlyApplicationDeliveryArbiter
    nonisolated private let injectedNowUptimeNanoseconds: (@Sendable () -> UInt64)?

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
    private var consumedApplicationDeliveryIDs: Set<UUID> = []

    public init() {
        self.ledgerID = UUID()
        self.applicationReceiptIssuerID = UUID()
        self.applicationDeliveryArbiter = TuyaReadOnlyApplicationDeliveryArbiter()
        self.injectedNowUptimeNanoseconds = nil
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.ledgerID = UUID()
        self.applicationReceiptIssuerID = UUID()
        self.applicationDeliveryArbiter = TuyaReadOnlyApplicationDeliveryArbiter()
        self.injectedNowUptimeNanoseconds = nowUptimeNanoseconds
    }

    /// Synchronously timestamps trusted SDK callback delivery before any new task/actor hop.
    /// The receipt is tied to this exact ledger instance and is registered pending under the same
    /// lock used by watchdog liveness arbitration.
    public nonisolated func captureApplicationReceipt(
        for token: TuyaReadOnlyConnectionToken
    ) -> TuyaReadOnlyApplicationReceipt {
        applicationDeliveryArbiter.capture(
            for: token,
            issuerID: applicationReceiptIssuerID,
            nowUptimeNanoseconds: { [injectedNowUptimeNanoseconds] in
                injectedNowUptimeNanoseconds?() ?? DispatchTime.now().uptimeNanoseconds
            }
        )
    }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else {
            throw MutationError.connectionGenerationExhausted
        }

        generation += 1
        let token = TuyaReadOnlyConnectionToken(ledgerID: ledgerID, generation: generation)
        let now = currentMonotonicUptimeNanoseconds()

        applicationDeliveryArbiter.reset()
        consumedApplicationDeliveryIDs.removeAll(keepingCapacity: true)
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
        // A success callback is authoritative only after this same generation recorded an
        // explicit authentication-start event. The accepted method label cannot mint chronology.
        guard case .authenticating = authenticationState else {
            throw MutationError.invalidAuthenticationTransition
        }
        // Device Sharing establishes account/device authority, not BLE-session authentication.
        // Reject it before sampling the clock so failed provenance cannot mint authenticated
        // chronology or perturb the in-progress authentication state.
        guard method == .smartLifeAppSDK else {
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
    /// Pre-auth failure requires a prior authentication-start event and retains no provenance.
    /// A late failure after authenticated observations preserves already-earned chronology only as
    /// non-authorizing diagnostics. In both cases the token is retired so a delayed callback cannot
    /// revive this generation. Detecting the terminal does not manufacture a later liveness sample.
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

    /// Fail-closed terminal for an exact current generation when an internal lifecycle mutation
    /// cannot complete because chronology or another ledger invariant is no longer trustworthy.
    ///
    /// Unlike the ordinary lifecycle terminals, this method deliberately does not sample the
    /// monotonic clock. It exists so a clock/invariant failure cannot strand private callback
    /// authority merely because terminal cleanup would otherwise need the same failing clock.
    /// No liveness timestamp is advanced and already-earned authenticated chronology remains only
    /// diagnostic. This terminal is not evidence of Tuya account/membership source-authority loss.
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

    /// Retires the current generation when its source identity/ownership authority is no longer
    /// current even though a transport disconnect has not been proven.
    ///
    /// This terminal is deliberately distinct from both observation-continuity failure and BLE
    /// disconnect. It may close a generation before authentication completes or after accepted
    /// authentication/application observations. Already-earned post-auth chronology remains
    /// diagnostic-only and the invalidation instant never becomes a synthetic liveness receipt.
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

    /// Records only the presence and receipt time of a non-empty application-level update.
    ///
    /// This deliberately accepts no `Data`: the current SmartLife SDK surface provides a
    /// structured `dpsUpdate` dictionary, not byte-exact FD50 transport. Callers must not invent
    /// serialized bytes merely to satisfy this chronology gate.
    ///
    /// Continuity and the incomplete-session deadline are checked before the update may advance
    /// accepted chronology. A deadline-crossing callback cannot become the evidence that rescues
    /// the same expired generation.
    /// Compatibility admission for package callers that do not already own the synchronous SDK
    /// callback boundary. It validates current/authenticated/non-empty authority before issuing a
    /// same-ledger receipt, so rejected legacy calls cannot strand pending liveness arbitration.
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

        let receipt = captureApplicationReceipt(for: token)
        try recordApplicationUpdate(isNonEmpty: true, receipt: receipt, for: token)
    }

    /// Records a non-empty application update using its exact ledger-issued delivery chronology.
    /// A receipt can be consumed once only; token/issuer mismatch or replay cannot move readiness.
    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        receipt: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard receipt.token == token,
              receipt.issuerID == applicationReceiptIssuerID else {
            throw MutationError.invalidApplicationReceipt
        }
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }
        guard consumedApplicationDeliveryIDs.insert(receipt.deliveryID).inserted else {
            throw MutationError.applicationDeliveryReceiptAlreadyConsumed
        }
        guard applicationDeliveryArbiter.consume(receipt) else {
            throw MutationError.invalidApplicationReceipt
        }

        let now = receipt.receivedAtUptimeNanoseconds
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
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
    /// No telemetry or application payload is manufactured by this call, and a pre-auth poll can
    /// never lengthen the chronology later used by the physical stability gate.
    ///
    /// Once a real current liveness receipt reaches the package-owned 60-second incomplete-session
    /// horizon, the same canonical preflight decides whether this generation must terminate. The
    /// deadline is evaluated against the already-accepted prefix before the receipt can advance
    /// chronology. If the generation is still incomplete, the package atomically records the
    /// bounded preflight failure and retires callback authority before throwing the semantic
    /// terminal for app-local mirroring.
    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        // Sampling is serialized with synchronous callback delivery. A receipt already pending for
        // this exact token wins chronology and makes this watchdog mutation yield without inventing
        // a later liveness instant.
        guard let now = applicationDeliveryArbiter.livenessSampleIfUnblocked(
            for: token,
            nowUptimeNanoseconds: { [injectedNowUptimeNanoseconds] in
                injectedNowUptimeNanoseconds?() ?? DispatchTime.now().uptimeNanoseconds
            }
        ) else {
            return
        }
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    /// Seals a failed observation horizon while authenticated transport may still exist.
    /// This is not a claim that BLE disconnected. Earned chronology remains diagnostic-only while
    /// callback authority is permanently retired. The failure keeps the last *actual* liveness
    /// observation; detecting the gap does not move that horizon forward.
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

    /// Explicit compatibility terminal for callers that independently detect an incomplete
    /// authenticated observation before the package-owned mutation boundary does. It does not
    /// claim that BLE disconnected and its reason covers insufficient repeated evidence, including
    /// sessions that legitimately observed one application update.
    public func markApplicationObservationTimedOut(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
    }

    /// Freezes an already-earned canonical ready verdict without manufacturing a later receipt or
    /// extending its duration. Retiring the token makes the accepted prefix immutable.
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

    /// Records an actual current connection-end boundary. Callers must not use this merely because
    /// app observation continuity became untrustworthy; use `markObservationContinuityInvalidated`.
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

    nonisolated private func currentMonotonicUptimeNanoseconds() -> UInt64 {
        injectedNowUptimeNanoseconds?() ?? DispatchTime.now().uptimeNanoseconds
    }

    private func nextMonotonicObservation() throws -> UInt64 {
        let now = currentMonotonicUptimeNanoseconds()
        if let latestObservedUptimeNanoseconds,
           now < latestObservedUptimeNanoseconds {
            throw MutationError.monotonicClockRegressed
        }
        return now
    }

    /// Evaluates the bounded incomplete-session deadline against the already-accepted evidence
    /// prefix and incoming observation time. A deadline-crossing callback cannot become evidence
    /// for the same generation. If readiness was already earned, the generation remains valid.
    /// Otherwise this package mutation atomically preserves the accepted prefix, records the
    /// semantic bounded-preflight failure, and retires callback authority before throwing.
    private func requireIncompleteObservationHorizonOpen(at now: UInt64) throws {
        guard let authenticatedAt = authenticatedAtUptimeNanoseconds else {
            return
        }
        guard now >= authenticatedAt else {
            throw MutationError.monotonicClockRegressed
        }
        guard now - authenticatedAt >= TuyaAuthenticatedReadOnlyPreflight.maximumIncompleteObservationNanoseconds else {
            return
        }
        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: makeSnapshot()) != .readyForStationaryMapping else {
            return
        }
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
        throw MutationError.incompleteObservationHorizonReached
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
