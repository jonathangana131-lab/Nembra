import Foundation

/// Callback-facing handoff for Tuya's documented device-to-app transparent receive delegate.
///
/// The live Smart Life adapter should call `receive(payload:callbackDeviceID:)` directly from
/// `ThingSmartBLEManagerDelegate.bleReceiveTransparentData(_:devId:)`. The receipt is sealed
/// synchronously by `C7D09A22DocumentedTransparentReceiveIngress` before this type creates an
/// asynchronous task, preserving the exact package generation and Tuya device identity that
/// existed at the SDK callback boundary.
///
/// The later snapshot lookup is deliberately package-owned and may race with retirement. That is
/// safe: `record(_:preflightSnapshot:)` revalidates generation/authentication custody and rejects
/// stale or cross-generation receipts. This type never retries a rejected callback against a newer
/// snapshot or generation.
///
/// This handoff is read-only. It has no DP publish, transparent-write, pairing, reset, removal, or
/// unbind API. Tuya transparent bytes remain diagnostic transport evidence only and cannot mint
/// raw-FD50 characteristic custody, physical first acceptance, stationary mapping, telemetry
/// semantics, or control authority.
@MainActor
public final class C7D09A22DocumentedTransparentDelegateHandoff {
    public typealias PreflightSnapshotProvider = @MainActor () async -> TuyaAuthenticatedReadOnlyPreflightSnapshot?
    public typealias RecordObserver = @MainActor (C7D09A22DocumentedTransparentReceiveIngress.RecordResult?) -> Void

    private let ingress: C7D09A22DocumentedTransparentReceiveIngress
    private let preflightSnapshotProvider: PreflightSnapshotProvider
    private let recordObserver: RecordObserver?
    private var isRetired = true
    private var pendingRecordTail: Task<Void, Never>?

    public init(
        ingress: C7D09A22DocumentedTransparentReceiveIngress = .init(),
        preflightSnapshotProvider: @escaping PreflightSnapshotProvider,
        recordObserver: RecordObserver? = nil
    ) {
        self.ingress = ingress
        self.preflightSnapshotProvider = preflightSnapshotProvider
        self.recordObserver = recordObserver
    }

    /// Arms the exact authenticated package generation. Authentication chronology comes from the
    /// immutable package snapshot; no app-owned connection timestamp is accepted here.
    @discardableResult
    public func begin(
        connectionToken: TuyaReadOnlyConnectionToken,
        expectedDeviceID: String,
        authenticatedPreflightSnapshot: TuyaAuthenticatedReadOnlyPreflightSnapshot
    ) async -> Bool {
        await retire()
        let armed = await ingress.begin(
            connectionToken: connectionToken,
            expectedDeviceID: expectedDeviceID,
            authenticatedPreflightSnapshot: authenticatedPreflightSnapshot
        )
        isRetired = !armed
        return armed
    }

    /// Call synchronously from Tuya's documented transparent-receive delegate callback.
    ///
    /// Generation/device custody is captured before the asynchronous task is created. Empty,
    /// wrong-device, unowned, or retired callbacks therefore never reach the snapshot provider.
    /// Accepted receipts are serialized into one package-owned tail so a later diagnostic read can
    /// deterministically observe every callback accepted before that read without scheduler sleeps
    /// or retries. The tail never retries rejected data and never changes generation ownership.
    public func receive(payload: Data, callbackDeviceID: String) {
        guard !isRetired,
              let receipt = ingress.capture(payload: payload, callbackDeviceID: callbackDeviceID) else {
            return
        }

        let previousRecord = pendingRecordTail
        let recordTask = Task { @MainActor [weak self] in
            await previousRecord?.value
            guard let self, !self.isRetired,
                  let snapshot = await self.preflightSnapshotProvider() else {
                return
            }
            let result = await self.ingress.record(receipt, preflightSnapshot: snapshot)
            self.recordObserver?(result)
        }
        pendingRecordTail = recordTask
    }

    /// Waits for callbacks already admitted synchronously by this handoff to finish their
    /// package-owned authenticated record step. This is a diagnostic/evidence ordering barrier,
    /// not a transport retry, write, or authority escalation.
    private func drainAcceptedRecords() async {
        let tail = pendingRecordTail
        await tail?.value
    }

    /// Non-secret transport diagnostics only. A positive result still does not prove a raw FD50
    /// GATT service/characteristic tuple and therefore cannot satisfy physical first acceptance.
    public func diagnosticSnapshot() async -> C7D09A22DocumentedTransparentReceiveIngress.DiagnosticSnapshot? {
        guard !isRetired else { return nil }
        await drainAcceptedRecords()
        guard !isRetired else { return nil }
        return await ingress.diagnosticSnapshot()
    }

    /// Retires before releasing package custody. Any callback already sealed but not yet recorded
    /// is discarded by the local retirement check and by the ingress/session generation checks.
    public func retire() async {
        isRetired = true
        let tail = pendingRecordTail
        pendingRecordTail = nil
        await tail?.value
        await ingress.retire()
    }

    public var hasActiveGeneration: Bool {
        !isRetired && ingress.hasActiveGeneration
    }

    // Diagnostic transport evidence cannot authorize protocol meaning or scooter mutation.
    public var authorizesRawFD50CharacteristicCustody: Bool { false }
    public var authorizesPhysicalFirstAcceptance: Bool { false }
    public var authorizesStationaryMapping: Bool { false }
    public var authorizesTelemetrySemantics: Bool { false }
    public var authorizesControlWrites: Bool { false }
    public var authorizesPairingResetOrUnbind: Bool { false }
}
