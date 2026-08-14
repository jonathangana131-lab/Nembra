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

/// Opaque one-shot receipt issued by one exact ledger instance at synchronous application delivery.
/// No public initializer or static mint surface exposes its scalar timestamp, issuer identity, or
/// delivery sequence. The ledger-owned receipt authority consumes each delivery exactly once.
public struct TuyaReadOnlyApplicationReceipt: Sendable {
    fileprivate let issuerID: UUID
    fileprivate let token: TuyaReadOnlyConnectionToken
    fileprivate let deliverySequence: UInt64
    fileprivate let receivedAtUptimeNanoseconds: UInt64

    fileprivate init(
        issuerID: UUID,
        token: TuyaReadOnlyConnectionToken,
        deliverySequence: UInt64,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        self.issuerID = issuerID
        self.token = token
        self.deliverySequence = deliverySequence
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
}

/// Opaque one-shot receipt for a direct current-connection liveness sample. Application delivery
/// and watchdog liveness use the same ledger-owned issuer and injected monotonic clock domain, so
/// actor scheduling can never silently change which side of the strict horizon a sample belongs to.
public struct TuyaReadOnlyLivenessReceipt: Sendable {
    fileprivate let issuerID: UUID
    fileprivate let token: TuyaReadOnlyConnectionToken
    fileprivate let deliverySequence: UInt64
    fileprivate let observedAtUptimeNanoseconds: UInt64

    fileprivate init(
        issuerID: UUID,
        token: TuyaReadOnlyConnectionToken,
        deliverySequence: UInt64,
        observedAtUptimeNanoseconds: UInt64
    ) {
        self.issuerID = issuerID
        self.token = token
        self.deliverySequence = deliverySequence
        self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds
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
        case observationAdmissionSequenceExhausted
        case observationAdmissionInvalidOrConsumed
        case applicationAdmissionPending
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
    private let nowUptimeNanoseconds: @Sendable () -> UInt64
    nonisolated private let receiptAuthority: ReceiptAuthority

    private var generation: UInt64 = 0
    private var currentToken: TuyaReadOnlyConnectionToken? {
        didSet {
            guard oldValue != currentToken else { return }
            if let oldValue {
                receiptAuthority.retire(oldValue)
            }
            if let currentToken {
                receiptAuthority.activate(currentToken)
            }
        }
    }
    private var authenticationState: TuyaAuthenticatedReadOnlyPreflightSnapshot.AuthenticationState =
        .unavailable(reason: "No active Bluetooth connection.")
    private var authenticationMethod: TuyaReadOnlyAuthenticationMethod?
    private var connectionStartedAtUptimeNanoseconds: UInt64?
    private var authenticatedAtUptimeNanoseconds: UInt64?
    private var latestObservedUptimeNanoseconds: UInt64?
    private var applicationPayloadCount = 0
    private var latestApplicationPayloadUptimeNanoseconds: UInt64?

    public init() {
        let clock: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = clock
        self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: clock)
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
        self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: nowUptimeNanoseconds)
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

    /// Synchronously issues one one-shot application-delivery receipt from this exact ledger.
    /// The app calls this only at the trusted SmartLife callback edge, before its first new Task.
    /// The caller cannot choose timestamp, issuer identity, or delivery sequence.
    public nonisolated func captureApplicationReceipt(
        isNonEmpty: Bool,
        for token: TuyaReadOnlyConnectionToken
    ) throws -> TuyaReadOnlyApplicationReceipt {
        try receiptAuthority.captureApplicationReceipt(isNonEmpty: isNonEmpty, for: token)
    }

    /// Releases an issued application receipt that never reached actor consumption. A consumed or
    /// stale receipt is already absent, so this is intentionally idempotent and cannot restore it.
    public nonisolated func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {
        receiptAuthority.releaseApplicationReceipt(receipt)
    }

    /// Issues a one-shot direct-liveness receipt only when no earlier application delivery remains
    /// pending. This is the package-side arbitration boundary; the watchdog cannot bypass it with
    /// an app-local integer check or a later actor-entry timestamp.
    public nonisolated func captureLivenessReceipt(
        for token: TuyaReadOnlyConnectionToken
    ) throws -> TuyaReadOnlyLivenessReceipt {
        try receiptAuthority.captureLivenessReceipt(for: token)
    }

    /// Records only the presence and exact receipt time of a non-empty application-level update.
    /// Every receipt is bound to this ledger issuer + exact token + unique one-shot delivery ID.
    /// Replays are rejected before payload count/latest chronology can move.
    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        receipt: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        let now = try receiptAuthority.consumeApplicationReceipt(receipt, for: token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }

        try admitApplicationUpdate(at: now)
    }

    /// Consumes an exact direct-liveness receipt. An older liveness receipt may finish actor work
    /// after a later accepted application receipt; because it is one-shot and adds no new evidence,
    /// it is safely ignored instead of manufacturing a monotonic regression.
    public func observeCurrentConnection(
        receipt: TuyaReadOnlyLivenessReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        let now = try receiptAuthority.consumeLivenessReceipt(receipt, for: token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        if let latestObservedUptimeNanoseconds,
           now <= latestObservedUptimeNanoseconds {
            return
        }
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    /// Package-internal compatibility path for deterministic unit tests. Shipping app code cannot
    /// call this overload; production application evidence must consume an exact ledger receipt.
    func recordApplicationUpdate(
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
        try admitApplicationUpdate(at: now)
    }

    /// Package-internal compatibility path for deterministic unit tests. Shipping app liveness
    /// must pass through `captureLivenessReceipt` so pending application delivery can fence it.
    func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    private func admitApplicationUpdate(at now: UInt64) throws {
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

    private func nextMonotonicObservation() throws -> UInt64 {
        let now = nowUptimeNanoseconds()
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

    private final class ReceiptAuthority: @unchecked Sendable {
        private let lock = NSLock()
        private let issuerID = UUID()
        private let nowUptimeNanoseconds: @Sendable () -> UInt64
        private var activeToken: TuyaReadOnlyConnectionToken?
        private var nextDeliverySequence: UInt64 = 0
        private var lastIssuedUptimeNanoseconds: UInt64?
        private var pendingApplicationSequences: Set<UInt64> = []
        private var pendingLivenessSequences: Set<UInt64> = []

        init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
            self.nowUptimeNanoseconds = nowUptimeNanoseconds
        }

        func activate(_ token: TuyaReadOnlyConnectionToken) {
            lock.lock()
            defer { lock.unlock() }
            activeToken = token
            lastIssuedUptimeNanoseconds = nil
            pendingApplicationSequences.removeAll(keepingCapacity: true)
            pendingLivenessSequences.removeAll(keepingCapacity: true)
        }

        func retire(_ token: TuyaReadOnlyConnectionToken) {
            lock.lock()
            defer { lock.unlock() }
            guard activeToken == token else { return }
            activeToken = nil
            lastIssuedUptimeNanoseconds = nil
            pendingApplicationSequences.removeAll(keepingCapacity: true)
            pendingLivenessSequences.removeAll(keepingCapacity: true)
        }

        func captureApplicationReceipt(
            isNonEmpty: Bool,
            for token: TuyaReadOnlyConnectionToken
        ) throws -> TuyaReadOnlyApplicationReceipt {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            guard isNonEmpty else { throw MutationError.emptyApplicationUpdate }
            let (sequence, now) = try issueNextReceipt()
            pendingApplicationSequences.insert(sequence)
            return TuyaReadOnlyApplicationReceipt(
                issuerID: issuerID,
                token: token,
                deliverySequence: sequence,
                receivedAtUptimeNanoseconds: now
            )
        }

        func captureLivenessReceipt(
            for token: TuyaReadOnlyConnectionToken
        ) throws -> TuyaReadOnlyLivenessReceipt {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            guard pendingApplicationSequences.isEmpty else {
                throw MutationError.applicationAdmissionPending
            }
            let (sequence, now) = try issueNextReceipt()
            pendingLivenessSequences.insert(sequence)
            return TuyaReadOnlyLivenessReceipt(
                issuerID: issuerID,
                token: token,
                deliverySequence: sequence,
                observedAtUptimeNanoseconds: now
            )
        }

        func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {
            lock.lock()
            defer { lock.unlock() }
            guard receipt.issuerID == issuerID else { return }
            pendingApplicationSequences.remove(receipt.deliverySequence)
        }

        func consumeApplicationReceipt(
            _ receipt: TuyaReadOnlyApplicationReceipt,
            for token: TuyaReadOnlyConnectionToken
        ) throws -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            guard receipt.issuerID == issuerID,
                  receipt.token == token,
                  pendingApplicationSequences.remove(receipt.deliverySequence) != nil else {
                throw MutationError.observationAdmissionInvalidOrConsumed
            }
            return receipt.receivedAtUptimeNanoseconds
        }

        func consumeLivenessReceipt(
            _ receipt: TuyaReadOnlyLivenessReceipt,
            for token: TuyaReadOnlyConnectionToken
        ) throws -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            try requireActive(token)
            guard receipt.issuerID == issuerID,
                  receipt.token == token,
                  pendingLivenessSequences.remove(receipt.deliverySequence) != nil else {
                throw MutationError.observationAdmissionInvalidOrConsumed
            }
            return receipt.observedAtUptimeNanoseconds
        }

        private func requireActive(_ token: TuyaReadOnlyConnectionToken) throws {
            guard let activeToken else { throw MutationError.noActiveConnection }
            guard activeToken == token else { throw MutationError.staleConnection }
        }

        private func issueNextReceipt() throws -> (UInt64, UInt64) {
            guard nextDeliverySequence < UInt64.max else {
                throw MutationError.observationAdmissionSequenceExhausted
            }
            let now = nowUptimeNanoseconds()
            if let lastIssuedUptimeNanoseconds,
               now < lastIssuedUptimeNanoseconds {
                throw MutationError.monotonicClockRegressed
            }
            nextDeliverySequence += 1
            lastIssuedUptimeNanoseconds = now
            return (nextDeliverySequence, now)
        }
    }

}
