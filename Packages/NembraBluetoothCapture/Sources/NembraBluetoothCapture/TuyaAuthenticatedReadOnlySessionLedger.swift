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

/// Opaque package-issued receipt for one application callback delivery.
///
/// The exact ledger instance binds its own issuer identity and monotonic clock. Public clients may
/// hold the receipt but cannot construct, timestamp, or replay it into accepted evidence.
public struct TuyaReadOnlyApplicationReceipt: Sendable {
    fileprivate let token: TuyaReadOnlyConnectionToken
    fileprivate let issuerID: UUID
    fileprivate let deliveryID: UUID
    fileprivate let receivedAtUptimeNanoseconds: UInt64
    fileprivate let nonEmptyApplicationDeliveryOccurred: Bool

    fileprivate init(
        token: TuyaReadOnlyConnectionToken,
        issuerID: UUID,
        deliveryID: UUID,
        receivedAtUptimeNanoseconds: UInt64,
        nonEmptyApplicationDeliveryOccurred: Bool
    ) {
        self.token = token
        self.issuerID = issuerID
        self.deliveryID = deliveryID
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.nonEmptyApplicationDeliveryOccurred = nonEmptyApplicationDeliveryOccurred
    }
}

/// Lock-bounded synchronous authority shared by SDK callback delivery and package liveness.
///
/// A callback receipt is registered under this lock before control returns to the SDK. Liveness
/// samples use the same lock and the same injected monotonic clock, so an already-delivered pending
/// callback cannot be overtaken by a watchdog actor hop. Delivery IDs are one-shot and consumed in
/// receipt order; scheduler order never becomes physical evidence order.
private final class TuyaApplicationDeliveryArbiter: @unchecked Sendable {
    enum ConsumeResult {
        case accepted
        case invalidApplicationReceipt
        case duplicateApplicationReceipt
        case applicationReceiptOrderPending
    }

    enum LivenessBoundaryResult {
        case sampled(UInt64)
        case applicationReceiptPending
        case invalidToken
    }

    enum SealAdmissionResult {
        case admitted
        case applicationReceiptPending
        case invalidToken
    }

    let applicationReceiptIssuerID: UUID
    private let lock = NSLock()
    private let nowUptimeNanoseconds: @Sendable () -> UInt64
    private var activeToken: TuyaReadOnlyConnectionToken?
    private var pendingApplicationDeliveries: [TuyaReadOnlyApplicationReceipt] = []
    private var consumedApplicationDeliveryIDs: Set<UUID> = []

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.applicationReceiptIssuerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
    }

    func reset() {
        lock.lock()
        activeToken = nil
        pendingApplicationDeliveries.removeAll(keepingCapacity: false)
        consumedApplicationDeliveryIDs.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    func activate(for token: TuyaReadOnlyConnectionToken) {
        lock.lock()
        activeToken = token
        pendingApplicationDeliveries.removeAll(keepingCapacity: true)
        consumedApplicationDeliveryIDs.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    func retire(for token: TuyaReadOnlyConnectionToken) {
        lock.lock()
        if activeToken == token {
            activeToken = nil
            pendingApplicationDeliveries.removeAll(keepingCapacity: false)
            consumedApplicationDeliveryIDs.removeAll(keepingCapacity: false)
        }
        lock.unlock()
    }

    func captureApplicationDelivery(for token: TuyaReadOnlyConnectionToken) -> TuyaReadOnlyApplicationReceipt? {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return nil }
        let receipt = TuyaReadOnlyApplicationReceipt(
            token: token,
            issuerID: applicationReceiptIssuerID,
            deliveryID: UUID(),
            receivedAtUptimeNanoseconds: nowUptimeNanoseconds(),
            nonEmptyApplicationDeliveryOccurred: true
        )
        pendingApplicationDeliveries.append(receipt)
        return receipt
    }

    func consumeApplicationReceipt(
        _ receipt: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) -> ConsumeResult {
        lock.lock()
        defer { lock.unlock() }

        guard activeToken == token,
              receipt.token == token,
              receipt.issuerID == applicationReceiptIssuerID else {
            return .invalidApplicationReceipt
        }
        guard !consumedApplicationDeliveryIDs.contains(receipt.deliveryID) else {
            return .duplicateApplicationReceipt
        }
        guard let first = pendingApplicationDeliveries.first else {
            return .invalidApplicationReceipt
        }
        guard first.deliveryID == receipt.deliveryID else {
            return pendingApplicationDeliveries.contains(where: { $0.deliveryID == receipt.deliveryID })
                ? .applicationReceiptOrderPending
                : .invalidApplicationReceipt
        }
        guard consumedApplicationDeliveryIDs.insert(receipt.deliveryID).inserted else {
            return .duplicateApplicationReceipt
        }
        pendingApplicationDeliveries.removeFirst()
        return .accepted
    }

    func captureLivenessBoundary(for token: TuyaReadOnlyConnectionToken) -> LivenessBoundaryResult {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return .invalidToken }
        guard pendingApplicationDeliveries.isEmpty else {
            return .applicationReceiptPending
        }
        let now = nowUptimeNanoseconds()
        return .sampled(now)
    }

    /// Atomically admits the immutable acceptance cut. A seal can proceed only when no
    /// application delivery is already pending, and successful admission simultaneously revokes
    /// all future synchronous receipt issuance for this generation before any seal-time clock
    /// sample occurs. This closes the check-then-retire race against nonisolated receipt minting.
    func beginSeal(for token: TuyaReadOnlyConnectionToken) -> SealAdmissionResult {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return .invalidToken }
        guard pendingApplicationDeliveries.isEmpty else {
            return .applicationReceiptPending
        }
        activeToken = nil
        pendingApplicationDeliveries.removeAll(keepingCapacity: false)
        consumedApplicationDeliveryIDs.removeAll(keepingCapacity: false)
        return .admitted
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
        case invalidApplicationReceipt
        case duplicateApplicationReceipt
        case applicationReceiptOrderPending
        case applicationReceiptPending
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
    private nonisolated let nowUptimeNanoseconds: @Sendable () -> UInt64
    private nonisolated let applicationDeliveryArbiter: TuyaApplicationDeliveryArbiter

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
        let clock: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = clock
        self.applicationDeliveryArbiter = TuyaApplicationDeliveryArbiter(nowUptimeNanoseconds: clock)
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
        self.applicationDeliveryArbiter = TuyaApplicationDeliveryArbiter(nowUptimeNanoseconds: nowUptimeNanoseconds)
    }

    @discardableResult
    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        applicationDeliveryArbiter.reset()
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
        applicationDeliveryArbiter.activate(for: token)
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
        applicationDeliveryArbiter.retire(for: token)
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

        applicationDeliveryArbiter.retire(for: token)
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
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.sourceAuthorityFailureReason)
        currentToken = nil
    }

    /// Synchronously receipts one application callback at the exact SDK-delivery boundary.
    /// The receipt is minted by this ledger instance, with this ledger's clock and one-shot issuer.
    nonisolated public func captureApplicationDelivery(
        for token: TuyaReadOnlyConnectionToken
    ) -> TuyaReadOnlyApplicationReceipt? {
        applicationDeliveryArbiter.captureApplicationDelivery(for: token)
    }

    /// Records only the presence and package-owned delivery time of a non-empty application update.
    public func recordApplicationUpdate(
        delivery: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard delivery.nonEmptyApplicationDeliveryOccurred else {
            throw MutationError.emptyApplicationUpdate
        }

        switch applicationDeliveryArbiter.consumeApplicationReceipt(delivery, for: token) {
        case .accepted:
            break
        case .invalidApplicationReceipt:
            throw MutationError.invalidApplicationReceipt
        case .duplicateApplicationReceipt:
            throw MutationError.duplicateApplicationReceipt
        case .applicationReceiptOrderPending:
            throw MutationError.applicationReceiptOrderPending
        }

        let now = delivery.receivedAtUptimeNanoseconds
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
        latestObservedUptimeNanoseconds = max(latestObservedUptimeNanoseconds ?? now, now)
    }

        /// Advances only non-secret liveness for the current authenticated connection.
    /// The liveness boundary is sampled under the same package lock and monotonic clock used by
    /// application delivery receipts. A pending delivered callback wins arbitration before this
    /// mutation can advance or terminalize the observation horizon.
    public func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }

        let livenessBoundary: UInt64
        switch applicationDeliveryArbiter.captureLivenessBoundary(for: token) {
        case .sampled(let now):
            livenessBoundary = now
        case .applicationReceiptPending:
            throw MutationError.applicationReceiptPending
        case .invalidToken:
            throw MutationError.invalidApplicationReceipt
        }
        let now = livenessBoundary
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    // Deterministic package-test compatibility only. Production clients outside this module cannot
    // call this overload; shipping app evidence must carry a one-shot public receipt.
    func recordApplicationUpdate(isNonEmpty: Bool, for token: TuyaReadOnlyConnectionToken) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }
        let now = try nextMonotonicObservation()
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)
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
        applicationDeliveryArbiter.retire(for: token)
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
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
    }

    /// Freezes an already-earned canonical ready verdict without manufacturing a later receipt or
    /// extending its duration. Retiring the token makes the accepted prefix immutable.
    public func sealAcceptedObservation(
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)

        // Receipt authority closes atomically before sampling any later actor-time boundary. An
        // already-delivered application callback therefore wins as pending, while a callback that
        // occurs after this cut can no longer mint evidence for the immutable accepted prefix.
        switch applicationDeliveryArbiter.beginSeal(for: token) {
        case .admitted:
            break
        case .applicationReceiptPending:
            throw MutationError.applicationReceiptPending
        case .invalidToken:
            throw MutationError.invalidApplicationReceipt
        }

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
        applicationDeliveryArbiter.retire(for: token)
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
        if let currentToken {
            applicationDeliveryArbiter.retire(for: currentToken)
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
            if let currentToken {
                applicationDeliveryArbiter.retire(for: currentToken)
            }
            authenticationState = .failed(reason: Self.observationContinuityFailureReason)
            currentToken = nil
            throw MutationError.observationContinuityInvalidated
        }
    }
}
