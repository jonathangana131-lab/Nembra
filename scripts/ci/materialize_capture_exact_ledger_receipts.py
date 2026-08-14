#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one target, found {count}: {old[:140]!r}")
    p.write_text(text.replace(old, new, 1))


ledger_path = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
ledger = Path(ledger_path)
text = ledger.read_text()

old_receipt_start = text.index("/// Opaque monotonic receipt minted at the exact synchronous application-callback delivery edge.")
old_receipt_end = text.index("/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.", old_receipt_start)
new_receipts = '''/// Opaque one-shot receipt issued by one exact ledger instance at synchronous application delivery.\n/// No public initializer or static mint surface exposes its scalar timestamp, issuer identity, or\n/// delivery sequence. The ledger-owned receipt authority consumes each delivery exactly once.\npublic struct TuyaReadOnlyApplicationReceipt: Sendable {\n    fileprivate let issuerID: UUID\n    fileprivate let token: TuyaReadOnlyConnectionToken\n    fileprivate let deliverySequence: UInt64\n    fileprivate let receivedAtUptimeNanoseconds: UInt64\n\n    fileprivate init(\n        issuerID: UUID,\n        token: TuyaReadOnlyConnectionToken,\n        deliverySequence: UInt64,\n        receivedAtUptimeNanoseconds: UInt64\n    ) {\n        self.issuerID = issuerID\n        self.token = token\n        self.deliverySequence = deliverySequence\n        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds\n    }\n}\n\n/// Opaque one-shot receipt for a direct current-connection liveness sample. Application delivery\n/// and watchdog liveness use the same ledger-owned issuer and injected monotonic clock domain, so\n/// actor scheduling can never silently change which side of the strict horizon a sample belongs to.\npublic struct TuyaReadOnlyLivenessReceipt: Sendable {\n    fileprivate let issuerID: UUID\n    fileprivate let token: TuyaReadOnlyConnectionToken\n    fileprivate let deliverySequence: UInt64\n    fileprivate let observedAtUptimeNanoseconds: UInt64\n\n    fileprivate init(\n        issuerID: UUID,\n        token: TuyaReadOnlyConnectionToken,\n        deliverySequence: UInt64,\n        observedAtUptimeNanoseconds: UInt64\n    ) {\n        self.issuerID = issuerID\n        self.token = token\n        self.deliverySequence = deliverySequence\n        self.observedAtUptimeNanoseconds = observedAtUptimeNanoseconds\n    }\n}\n\n'''
text = text[:old_receipt_start] + new_receipts + text[old_receipt_end:]
ledger.write_text(text)

replace_once(
    ledger_path,
    '''        case applicationPayloadCountExhausted\n        case monotonicClockRegressed''',
    '''        case applicationPayloadCountExhausted\n        case observationAdmissionSequenceExhausted\n        case observationAdmissionInvalidOrConsumed\n        case applicationAdmissionPending\n        case monotonicClockRegressed'''
)

replace_once(
    ledger_path,
    '''    private let ledgerID: UUID\n    private let nowUptimeNanoseconds: @Sendable () -> UInt64\n\n    private var generation: UInt64 = 0\n    private var currentToken: TuyaReadOnlyConnectionToken?''',
    '''    private let ledgerID: UUID\n    private let nowUptimeNanoseconds: @Sendable () -> UInt64\n    nonisolated private let receiptAuthority: ReceiptAuthority\n\n    private var generation: UInt64 = 0\n    private var currentToken: TuyaReadOnlyConnectionToken? {\n        didSet {\n            guard oldValue != currentToken else { return }\n            if let oldValue {\n                receiptAuthority.retire(oldValue)\n            }\n            if let currentToken {\n                receiptAuthority.activate(currentToken)\n            }\n        }\n    }'''
)

replace_once(
    ledger_path,
    '''    public init() {\n        self.ledgerID = UUID()\n        self.nowUptimeNanoseconds = { DispatchTime.now().uptimeNanoseconds }\n    }\n\n    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {\n        self.ledgerID = UUID()\n        self.nowUptimeNanoseconds = nowUptimeNanoseconds\n    }''',
    '''    public init() {\n        let clock: @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }\n        self.ledgerID = UUID()\n        self.nowUptimeNanoseconds = clock\n        self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: clock)\n    }\n\n    init(nowUptimeNanoseconds: @escaping @Sendable () -> UInt64) {\n        self.ledgerID = UUID()\n        self.nowUptimeNanoseconds = nowUptimeNanoseconds\n        self.receiptAuthority = ReceiptAuthority(nowUptimeNanoseconds: nowUptimeNanoseconds)\n    }'''
)

text = ledger.read_text()
section_start = text.index("    /// Records only the presence and receipt time of a non-empty application-level update.")
section_end = text.index("    /// Seals a failed observation horizon while authenticated transport may still exist.", section_start)
new_section = '''    /// Synchronously issues one one-shot application-delivery receipt from this exact ledger.\n    /// The app calls this only at the trusted SmartLife callback edge, before its first new Task.\n    /// The caller cannot choose timestamp, issuer identity, or delivery sequence.\n    public nonisolated func captureApplicationReceipt(\n        isNonEmpty: Bool,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws -> TuyaReadOnlyApplicationReceipt {\n        try receiptAuthority.captureApplicationReceipt(isNonEmpty: isNonEmpty, for: token)\n    }\n\n    /// Releases an issued application receipt that never reached actor consumption. A consumed or\n    /// stale receipt is already absent, so this is intentionally idempotent and cannot restore it.\n    public nonisolated func releaseApplicationReceipt(_ receipt: TuyaReadOnlyApplicationReceipt) {\n        receiptAuthority.releaseApplicationReceipt(receipt)\n    }\n\n    /// Issues a one-shot direct-liveness receipt only when no earlier application delivery remains\n    /// pending. This is the package-side arbitration boundary; the watchdog cannot bypass it with\n    /// an app-local integer check or a later actor-entry timestamp.\n    public nonisolated func captureLivenessReceipt(\n        for token: TuyaReadOnlyConnectionToken\n    ) throws -> TuyaReadOnlyLivenessReceipt {\n        try receiptAuthority.captureLivenessReceipt(for: token)\n    }\n\n    /// Records only the presence and exact receipt time of a non-empty application-level update.\n    /// Every receipt is bound to this ledger issuer + exact token + unique one-shot delivery ID.\n    /// Replays are rejected before payload count/latest chronology can move.\n    public func recordApplicationUpdate(\n        isNonEmpty: Bool,\n        receipt: TuyaReadOnlyApplicationReceipt,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        let now = try receiptAuthority.consumeApplicationReceipt(receipt, for: token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        guard isNonEmpty else {\n            throw MutationError.emptyApplicationUpdate\n        }\n\n        try admitApplicationUpdate(at: now)\n    }\n\n    /// Consumes an exact direct-liveness receipt. An older liveness receipt may finish actor work\n    /// after a later accepted application receipt; because it is one-shot and adds no new evidence,\n    /// it is safely ignored instead of manufacturing a monotonic regression.\n    public func observeCurrentConnection(\n        receipt: TuyaReadOnlyLivenessReceipt,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        let now = try receiptAuthority.consumeLivenessReceipt(receipt, for: token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        if let latestObservedUptimeNanoseconds,\n           now <= latestObservedUptimeNanoseconds {\n            return\n        }\n        try requireContinuousAuthenticatedObservation(at: now)\n        try requireIncompleteObservationHorizonOpen(at: now)\n        latestObservedUptimeNanoseconds = now\n    }\n\n    /// Package-internal compatibility path for deterministic unit tests. Shipping app code cannot\n    /// call this overload; production application evidence must consume an exact ledger receipt.\n    func recordApplicationUpdate(\n        isNonEmpty: Bool,\n        for token: TuyaReadOnlyConnectionToken\n    ) throws {\n        try requireCurrent(token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        guard isNonEmpty else {\n            throw MutationError.emptyApplicationUpdate\n        }\n        let now = try nextMonotonicObservation()\n        try admitApplicationUpdate(at: now)\n    }\n\n    /// Package-internal compatibility path for deterministic unit tests. Shipping app liveness\n    /// must pass through `captureLivenessReceipt` so pending application delivery can fence it.\n    func observeCurrentConnection(for token: TuyaReadOnlyConnectionToken) throws {\n        try requireCurrent(token)\n        guard case .authenticated = authenticationState else {\n            throw MutationError.authenticationRequired\n        }\n        let now = try nextMonotonicObservation()\n        try requireContinuousAuthenticatedObservation(at: now)\n        try requireIncompleteObservationHorizonOpen(at: now)\n        latestObservedUptimeNanoseconds = now\n    }\n\n    private func admitApplicationUpdate(at now: UInt64) throws {\n        try requireContinuousAuthenticatedObservation(at: now)\n        try requireIncompleteObservationHorizonOpen(at: now)\n        guard let authenticatedAt = authenticatedAtUptimeNanoseconds,\n              now >= authenticatedAt else {\n            throw MutationError.monotonicClockRegressed\n        }\n        guard applicationPayloadCount < Int.max else {\n            throw MutationError.applicationPayloadCountExhausted\n        }\n\n        applicationPayloadCount += 1\n        latestApplicationPayloadUptimeNanoseconds = now\n        latestObservedUptimeNanoseconds = now\n    }\n\n'''
text = text[:section_start] + new_section + text[section_end:]
ledger.write_text(text)

# Add the exact-ledger receipt authority as a nested implementation detail. It shares the actor's
# injected clock closure but uses its own lock so callback delivery can be receipted synchronously
# before any actor hop.
text = ledger.read_text()
insert_at = text.rfind("\n}")
if insert_at < 0:
    raise SystemExit("ledger actor closing brace not found")
authority = r'''

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
'''
text = text[:insert_at] + authority + text[insert_at:]
ledger.write_text(text)

app_path = "NembraApp/App/NembraCaptureEntrypoint.swift"
replace_once(
    app_path,
    '''                    onApplicationUpdate: { [weak self] update in\n                        guard let self, !update.isEmpty else { return }\n                        let applicationReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)\n                        self.applicationUpdateAdmissionsInFlight += 1\n                        let predecessor = self.applicationUpdateAdmissionTail\n                        let admissionTask = Task { @MainActor [weak self] in\n                            _ = await predecessor?.value\n                            guard let self else { return }\n                            defer { self.applicationUpdateAdmissionsInFlight -= 1 }\n                            await self.receivedApplicationUpdate(\n                                update,\n                                receipt: applicationReceipt,\n                                token: token\n                            )\n                        }\n                        self.applicationUpdateAdmissionTail = admissionTask\n                    },''',
    '''                    onApplicationUpdate: { [weak self] update in\n                        guard let self,\n                              !update.isEmpty,\n                              self.currentConnectionToken == token,\n                              !self.acceptanceCutIsClosed else { return }\n\n                        let applicationReceipt: TuyaReadOnlyApplicationReceipt\n                        do {\n                            applicationReceipt = try self.sessionLedger.captureApplicationReceipt(\n                                isNonEmpty: true,\n                                for: token\n                            )\n                        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {\n                            return\n                        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {\n                            return\n                        } catch {\n                            Task { @MainActor [weak self] in\n                                await self?.invalidateInternalLifecycle(\n                                    token: token,\n                                    message: "Application callback admission failed closed before scheduler handoff: \\(error.localizedDescription)",\n                                    kind: "application_delivery_admission_failed"\n                                )\n                            }\n                            return\n                        }\n\n                        self.applicationUpdateAdmissionsInFlight += 1\n                        let predecessor = self.applicationUpdateAdmissionTail\n                        let ledger = self.sessionLedger\n                        let admissionTask = Task { @MainActor [weak self] in\n                            _ = await predecessor?.value\n                            defer { ledger.releaseApplicationReceipt(applicationReceipt) }\n                            guard let self else { return }\n                            defer { self.applicationUpdateAdmissionsInFlight -= 1 }\n                            await self.receivedApplicationUpdate(\n                                update,\n                                receipt: applicationReceipt,\n                                token: token\n                            )\n                        }\n                        self.applicationUpdateAdmissionTail = admissionTask\n                    },'''
)

replace_once(
    app_path,
    '''                self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)\n                guard self.sdkLocalBLEOnline else {\n                    await self.recordObservedTransportLoss(token: token)\n                    return\n                }\n\n                do {\n                    try await self.sessionLedger.observeCurrentConnection(for: token)''',
    '''                self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)\n                guard self.sdkLocalBLEOnline else {\n                    await self.recordObservedTransportLoss(token: token)\n                    return\n                }\n\n                let livenessReceipt: TuyaReadOnlyLivenessReceipt\n                do {\n                    livenessReceipt = try self.sessionLedger.captureLivenessReceipt(for: token)\n                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.applicationAdmissionPending {\n                    try? await Task.sleep(for: .milliseconds(10))\n                    continue\n                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {\n                    return\n                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {\n                    return\n                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: "Liveness receipt issuance failed closed because monotonic chronology regressed.",\n                        kind: "liveness_receipt_clock_regressed"\n                    )\n                    return\n                } catch {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: "Liveness receipt issuance violated the current internal session lifecycle: \\(error.localizedDescription)",\n                        kind: "liveness_receipt_admission_failed"\n                    )\n                    return\n                }\n\n                do {\n                    try await self.sessionLedger.observeCurrentConnection(\n                        receipt: livenessReceipt,\n                        for: token\n                    )'''
)

# Production application record still carries the real update's non-empty bit, but chronology is
# now consumed from the exact-ledger one-shot receipt rather than a caller-minted timestamp.
app = Path(app_path)
app_text = app.read_text()
assert "TuyaReadOnlyApplicationReceipt.capture(for:" not in app_text
assert "captureApplicationReceipt(" in app_text
assert "captureLivenessReceipt(for: token)" in app_text
assert "observeCurrentConnection(\n                        receipt: livenessReceipt" in app_text
assert "defer { ledger.releaseApplicationReceipt(applicationReceipt) }" in app_text

ledger_text = ledger.read_text()
assert "public static func capture" not in ledger_text
assert "nonisolated private let receiptAuthority" in ledger_text
assert "applicationAdmissionPending" in ledger_text
assert "pendingApplicationSequences.remove(receipt.deliverySequence) != nil" in ledger_text
assert "func observeCurrentConnection(for token" in ledger_text
assert "public func observeCurrentConnection(for token" not in ledger_text

Path(".github/workflows/capture-exact-ledger-receipt-materializer.yml").unlink()
Path(__file__).unlink()
