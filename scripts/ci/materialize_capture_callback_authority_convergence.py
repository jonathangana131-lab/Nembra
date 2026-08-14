#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_section(text: str, start: str, end: str, replacement: str, label: str) -> str:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"{label}: start marker missing")
    if text.find(start, a + 1) >= 0:
        raise SystemExit(f"{label}: start marker not unique")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"{label}: end marker missing")
    return text[:a] + replacement + text[b:]


def materialize_ledger() -> None:
    path = ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
    text = path.read_text(encoding="utf-8")

    receipt_and_arbiter = r'''/// Opaque package-issued receipt for one application callback delivery.
///
/// The exact ledger instance binds its own issuer identity and monotonic clock. Public clients may
/// hold the receipt but cannot construct, timestamp, or replay it into accepted evidence.
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

    func captureApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> TuyaReadOnlyApplicationReceipt? {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return nil }
        let receipt = TuyaReadOnlyApplicationReceipt(
            token: token,
            issuerID: applicationReceiptIssuerID,
            deliveryID: UUID(),
            receivedAtUptimeNanoseconds: nowUptimeNanoseconds()
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

    func hasPendingApplicationReceipt(for token: TuyaReadOnlyConnectionToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard activeToken == token else { return false }
        return !pendingApplicationDeliveries.isEmpty
    }
}

'''
    text = replace_once(
        text,
        "/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.\n",
        receipt_and_arbiter + "/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.\n",
        "receipt/arbiter insertion",
    )

    text = replace_once(
        text,
        "        case applicationPayloadCountExhausted\n        case monotonicClockRegressed\n",
        "        case applicationPayloadCountExhausted\n        case invalidApplicationReceipt\n        case duplicateApplicationReceipt\n        case applicationReceiptOrderPending\n        case applicationReceiptPending\n        case monotonicClockRegressed\n",
        "receipt mutation errors",
    )

    text = replace_once(
        text,
        "    private let ledgerID: UUID\n    private let nowUptimeNanoseconds: @Sendable () -> UInt64\n",
        "    private let ledgerID: UUID\n    private nonisolated let nowUptimeNanoseconds: @Sendable () -> UInt64\n    private nonisolated let applicationDeliveryArbiter: TuyaApplicationDeliveryArbiter\n",
        "shared clock/arbiter properties",
    )

    text = replace_once(
        text,
        '''    public init() {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds }
    }

    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {
        self.ledgerID = UUID()
        self.nowUptimeNanoseconds = nowUptimeNanoseconds
    }
''',
        '''    public init() {
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
''',
        "ledger initializers",
    )

    text = replace_once(
        text,
        '''    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        guard generation < UInt64.max else {
''',
        '''    public func beginConnection() throws -> TuyaReadOnlyConnectionToken {
        applicationDeliveryArbiter.reset()
        guard generation < UInt64.max else {
''',
        "begin connection arbiter reset",
    )

    text = replace_once(
        text,
        '''        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
    }

    /// Retires current session authority when the official SDK reports a terminal failure.
''',
        '''        applicationPayloadCount = 0
        latestApplicationPayloadUptimeNanoseconds = nil
        applicationDeliveryArbiter.activate(for: token)
    }

    /// Retires current session authority when the official SDK reports a terminal failure.
''',
        "activate receipt authority after authentication",
    )

    # Every explicit terminal/seal retires synchronous callback receipt authority.
    terminal_replacements = [
        (
            '''        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: "Tuya SDK session failed.")
        currentToken = nil
''',
            '''        _ = try nextMonotonicObservation()
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: "Tuya SDK session failed.")
        currentToken = nil
''',
            "authentication-failed receipt retirement",
        ),
        (
            '''        authenticationState = .failed(reason: Self.internalLifecycleFailureReason)
        currentToken = nil
''',
            '''        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.internalLifecycleFailureReason)
        currentToken = nil
''',
            "internal-terminal receipt retirement",
        ),
        (
            '''        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.sourceAuthorityFailureReason)
        currentToken = nil
''',
            '''        _ = try nextMonotonicObservation()
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.sourceAuthorityFailureReason)
        currentToken = nil
''',
            "source-terminal receipt retirement",
        ),
    ]
    for old, new, label in terminal_replacements:
        text = replace_once(text, old, new, label)

    record_and_capture = r'''    /// Synchronously receipts one application callback at the exact SDK-delivery boundary.
    /// The receipt is minted by this ledger instance, with this ledger's clock and one-shot issuer.
    nonisolated public func captureApplicationReceipt(
        for token: TuyaReadOnlyConnectionToken
    ) -> TuyaReadOnlyApplicationReceipt? {
        applicationDeliveryArbiter.captureApplicationReceipt(for: token)
    }

    /// Records only the presence and package-owned delivery time of a non-empty application update.
    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        receipt: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }

        switch applicationDeliveryArbiter.consumeApplicationReceipt(receipt, for: token) {
        case .accepted:
            break
        case .invalidApplicationReceipt:
            throw MutationError.invalidApplicationReceipt
        case .duplicateApplicationReceipt:
            throw MutationError.duplicateApplicationReceipt
        case .applicationReceiptOrderPending:
            throw MutationError.applicationReceiptOrderPending
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
        latestObservedUptimeNanoseconds = max(latestObservedUptimeNanoseconds ?? now, now)
    }

    '''
    text = replace_section(
        text,
        "    /// Records only the presence and receipt time of a non-empty application-level update.",
        "    /// Advances only the non-secret liveness observation for the current authenticated connection.",
        record_and_capture,
        "public application receipt mutation",
    )

    observe_replacement = r'''    /// Advances only non-secret liveness for the current authenticated connection.
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

    '''
    text = replace_section(
        text,
        "    /// Advances only the non-secret liveness observation for the current authenticated connection.",
        "    /// Seals a failed observation horizon while authenticated transport may still exist.",
        observe_replacement,
        "liveness arbitration mutation",
    )

    text = replace_once(
        text,
        '''        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.observationContinuityFailureReason)
        currentToken = nil
''',
        '''        _ = try nextMonotonicObservation()
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.observationContinuityFailureReason)
        currentToken = nil
''',
        "explicit continuity terminal receipt retirement",
    )
    text = replace_once(
        text,
        '''        _ = try nextMonotonicObservation()
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
''',
        '''        _ = try nextMonotonicObservation()
        applicationDeliveryArbiter.retire(for: token)
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
''',
        "explicit incomplete terminal receipt retirement",
    )
    text = replace_once(
        text,
        '''        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        currentToken = nil
''',
        '''        guard TuyaAuthenticatedReadOnlyPreflight.verdict(for: snapshot) == .readyForStationaryMapping else {
            throw MutationError.preflightNotReady
        }
        guard !applicationDeliveryArbiter.hasPendingApplicationReceipt(for: token) else {
            throw MutationError.applicationReceiptPending
        }
        applicationDeliveryArbiter.retire(for: token)
        currentToken = nil
''',
        "accepted seal receipt retirement",
    )
    text = replace_once(
        text,
        '''        let now = try nextMonotonicObservation()
        currentToken = nil
        authenticationState = .unavailable(reason: "Bluetooth connection ended.")
''',
        '''        let now = try nextMonotonicObservation()
        applicationDeliveryArbiter.retire(for: token)
        currentToken = nil
        authenticationState = .unavailable(reason: "Bluetooth connection ended.")
''',
        "disconnect receipt retirement",
    )

    text = replace_once(
        text,
        '''        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
        throw MutationError.incompleteObservationHorizonReached
''',
        '''        if let currentToken {
            applicationDeliveryArbiter.retire(for: currentToken)
        }
        authenticationState = .failed(reason: Self.incompleteObservationFailureReason)
        currentToken = nil
        throw MutationError.incompleteObservationHorizonReached
''',
        "implicit incomplete terminal receipt retirement",
    )
    text = replace_once(
        text,
        '''        guard now - latest <= Self.maximumContinuousObservationGapNanoseconds else {
            authenticationState = .failed(reason: Self.observationContinuityFailureReason)
            currentToken = nil
            throw MutationError.observationContinuityInvalidated
        }
''',
        '''        guard now - latest <= Self.maximumContinuousObservationGapNanoseconds else {
            if let currentToken {
                applicationDeliveryArbiter.retire(for: currentToken)
            }
            authenticationState = .failed(reason: Self.observationContinuityFailureReason)
            currentToken = nil
            throw MutationError.observationContinuityInvalidated
        }
''',
        "implicit continuity terminal receipt retirement",
    )

    path.write_text(text, encoding="utf-8")


def materialize_app() -> None:
    path = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
    text = path.read_text(encoding="utf-8")

    text = replace_once(
        text,
        '''    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    )
''',
        '''    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @MainActor @escaping ([String: String]) -> Void,
        sourceAuthorityFailure: @escaping () -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    )
''',
        "official driver protocol",
    )

    text = replace_once(
        text,
        '''                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },
                    success: { [weak self] in
''',
        '''                    onApplicationUpdate: { [weak self] update in
                        self?.admitApplicationUpdateCallback(update, token: token)
                    },
                    sourceAuthorityFailure: { [weak self] in
                        Task { @MainActor in
                            guard let self else { return }
                            await self.invalidateSourceAuthority(
                                token: token,
                                message: "SmartLife application callback source no longer matched the selected scooter. The generation was retired without admitting that payload.",
                                kind: "sdk_application_callback_source_mismatch"
                            )
                        }
                    },
                    success: { [weak self] in
''',
        "synchronous application admission",
    )

    admission_helper = r'''    private func admitApplicationUpdateCallback(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) {
        guard !update.isEmpty else { return }
        guard currentConnectionToken == token else {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .observing else {
            log("application_update_outside_observation_ignored", [
                "generation": String(token.diagnosticGeneration),
                "phase": phase.rawValue
            ])
            return
        }
        guard !acceptanceCutIsClosed else {
            log("application_update_after_acceptance_cut_ignored", [
                "generation": String(token.diagnosticGeneration)
            ])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateSourceAuthority(
                    token: token,
                    message: "SDK account/device source authority changed before callback receipt admission.",
                    kind: "sdk_source_authority_changed_before_callback_receipt"
                )
            }
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            Task { @MainActor [weak self] in
                await self?.recordObservedTransportLoss(token: token)
            }
            return
        }
        guard let applicationReceipt = sessionLedger.captureApplicationReceipt(for: token) else {
            log("application_receipt_authority_unavailable", ["generation": String(token.diagnosticGeneration)])
            return
        }

        applicationUpdateAdmissionsInFlight += 1
        Task { @MainActor [self] in
            defer { applicationUpdateAdmissionsInFlight -= 1 }
            await receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)
        }
    }

'''
    text = replace_once(
        text,
        "    private func receivedApplicationUpdate(\n",
        admission_helper + "    private func receivedApplicationUpdate(\n",
        "application admission helper",
    )
    text = replace_once(
        text,
        '''    private func receivedApplicationUpdate(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) async {
''',
        '''    private func receivedApplicationUpdate(
        _ update: [String: String],
        receipt: TuyaReadOnlyApplicationReceipt,
        token: TuyaReadOnlyConnectionToken
    ) async {
''',
        "receipt-aware receiver signature",
    )
    text = replace_once(
        text,
        '''
        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        // Snapshot the exact account identity while the admission checks above are still
''',
        '''
        // Snapshot the exact account identity while the admission checks above are still
''',
        "move app drain before task hop",
    )
    text = replace_once(
        text,
        '''        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
''',
        '''        do {
            var applicationReceiptRecorded = false
            while !applicationReceiptRecorded {
                do {
                    try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, receipt: receipt, for: token)
                    applicationReceiptRecorded = true
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptOrderPending {
                    guard currentConnectionToken == token,
                          phase == .observing,
                          !acceptanceCutIsClosed else { return }
                    await Task.yield()
                }
            }
            await refreshLedgerSnapshot()
''',
        "ordered application receipt consumption",
    )

    text = replace_once(
        text,
        '''                guard self.sdkLocalBLEOnline else {
                    await self.recordObservedTransportLoss(token: token)
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
''',
        '''                guard self.sdkLocalBLEOnline else {
                    await self.recordObservedTransportLoss(token: token)
                    return
                }

                if self.applicationUpdateAdmissionsInFlight > 0 {
                    try? await Task.sleep(for: .milliseconds(25))
                    continue
                }
                guard self.applicationUpdateAdmissionsInFlight == 0 else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Application callback admission drain became internally inconsistent.",
                        kind: "application_admission_drain_invalid"
                    )
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
''',
        "watchdog app-side drain fence",
    )
    text = replace_once(
        text,
        '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
''',
        '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationReceiptPending {
                    try? await Task.sleep(for: .milliseconds(25))
                    continue
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
''',
        "watchdog package pending arbitration",
    )

    text = replace_once(
        text,
        '''private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var onApplicationUpdate: (([String: String]) -> Void)?
''',
        '''private final class SmartLifeDriver: NSObject, OfficialTuyaDriver, ThingSmartDeviceDelegate {
    private var device: ThingSmartDevice?
    private var expectedDeviceID: String?
    private var onApplicationUpdate: (@MainActor ([String: String]) -> Void)?
    private var onSourceAuthorityFailure: (() -> Void)?
''',
        "SmartLife source authority state",
    )
    text = replace_once(
        text,
        '''    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @escaping ([String: String]) -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure()
            return
        }
        self.onApplicationUpdate = onApplicationUpdate
        device = ThingSmartDevice(deviceId: deviceID)
''',
        '''    func connect(
        deviceID: String,
        uuid: String,
        productID: String,
        onApplicationUpdate: @MainActor @escaping ([String: String]) -> Void,
        sourceAuthorityFailure: @escaping () -> Void,
        success: @escaping () -> Void,
        failure: @escaping () -> Void
    ) {
        guard OfficialTuyaFactory.bootstrap() else {
            failure()
            return
        }
        expectedDeviceID = deviceID
        self.onApplicationUpdate = onApplicationUpdate
        onSourceAuthorityFailure = sourceAuthorityFailure
        device = ThingSmartDevice(deviceId: deviceID)
''',
        "SmartLife exact-device binding",
    )
    text = replace_once(
        text,
        '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let dps, !dps.isEmpty else { return }
''',
        '''    func device(_ device: ThingSmartDevice?, dpsUpdate dps: [AnyHashable: Any]?) {
        guard let callbackDeviceID = device?.deviceModel.devId,
              callbackDeviceID == expectedDeviceID else {
            onApplicationUpdate = nil
            self.device?.delegate = nil
            onSourceAuthorityFailure?()
            onSourceAuthorityFailure = nil
            expectedDeviceID = nil
            return
        }
        guard let dps, !dps.isEmpty else { return }
''',
        "SmartLife delegate source fence",
    )

    path.write_text(text, encoding="utf-8")


def update_source_contracts() -> None:
    path = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAcceptedApplicationEvidenceSealSourceTests.swift"
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        'body.range(of: "receivedApplicationUpdate(update, token: token)", range: task.upperBound..<body.endIndex)',
        'body.range(of: "receivedApplicationUpdate(update, receipt: applicationReceipt, token: token)", range: task.upperBound..<body.endIndex)',
        "accepted-seal receipt-aware receiver contract",
    )
    path.write_text(text, encoding="utf-8")


def main() -> int:
    materialize_ledger()
    materialize_app()
    update_source_contracts()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
