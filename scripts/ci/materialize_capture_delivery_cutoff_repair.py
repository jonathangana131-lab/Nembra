#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path}: expected exactly one replacement target, found {count}: {old[:120]!r}"
        )
    target.write_text(text.replace(old, new, 1))


ledger_path = "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift"
replace_once(
    ledger_path,
    "}\n\n/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.",
    """}

/// Opaque monotonic receipt minted at the exact synchronous application-callback delivery edge.
/// The caller can ask the package to capture "now" for an existing connection token, but cannot
/// choose the scalar timestamp carried by a production receipt. This lets later actor admission
/// preserve delivery chronology without turning a caller-selected number into evidence.
public struct TuyaReadOnlyApplicationReceipt: Sendable {
    fileprivate let token: TuyaReadOnlyConnectionToken
    fileprivate let receivedAtUptimeNanoseconds: UInt64

    public static func capture(for token: TuyaReadOnlyConnectionToken) -> Self {
        Self(
            token: token,
            receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    fileprivate init(
        token: TuyaReadOnlyConnectionToken,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        self.token = token
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }

    /// Package-internal deterministic clock injection used only by tests.
    static func testingCapture(
        for token: TuyaReadOnlyConnectionToken,
        receivedAtUptimeNanoseconds: UInt64
    ) -> Self {
        Self(token: token, receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds)
    }
}

/// Owns the non-secret chronology consumed by `TuyaAuthenticatedReadOnlyPreflight`.""",
)

replace_once(
    ledger_path,
    """    public func recordApplicationUpdate(
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
        try requireIncompleteObservationHorizonOpen(at: now)""",
    """    public func recordApplicationUpdate(
        isNonEmpty: Bool,
        receipt: TuyaReadOnlyApplicationReceipt,
        for token: TuyaReadOnlyConnectionToken
    ) throws {
        try requireCurrent(token)
        guard receipt.token == token else {
            throw MutationError.staleConnection
        }
        guard case .authenticated = authenticationState else {
            throw MutationError.authenticationRequired
        }
        guard isNonEmpty else {
            throw MutationError.emptyApplicationUpdate
        }

        let now = receipt.receivedAtUptimeNanoseconds
        try requireContinuousAuthenticatedObservation(at: now)
        try requireIncompleteObservationHorizonOpen(at: now)""",
)

replace_once(
    ledger_path,
    """        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    /// Seals a failed observation horizon while authenticated transport may still exist.""",
    """        try requireIncompleteObservationHorizonOpen(at: now)
        latestObservedUptimeNanoseconds = now
    }

    /// Package-internal compatibility path for existing deterministic fake-clock tests.
    /// Shipping app code cannot call this overload; production application evidence must carry an
    /// opaque synchronous `TuyaReadOnlyApplicationReceipt`.
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

    /// Seals a failed observation horizon while authenticated transport may still exist.""",
)

app_path = "NembraApp/App/NembraCaptureEntrypoint.swift"
replace_once(
    app_path,
    """    private var applicationUpdateAdmissionsInFlight = 0
    private var acceptanceCutIsClosed = false""",
    """    private var applicationUpdateAdmissionsInFlight = 0
    private var applicationUpdateAdmissionTail: Task<Void, Never>?
    private var acceptanceCutIsClosed = false""",
)

replace_once(
    app_path,
    """                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },""",
    """                    onApplicationUpdate: { [weak self] update in
                        guard let self, !update.isEmpty else { return }
                        let applicationReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)
                        self.applicationUpdateAdmissionsInFlight += 1
                        let predecessor = self.applicationUpdateAdmissionTail
                        let admissionTask = Task { @MainActor [weak self] in
                            _ = await predecessor?.value
                            guard let self else { return }
                            defer { self.applicationUpdateAdmissionsInFlight -= 1 }
                            await self.receivedApplicationUpdate(
                                update,
                                receipt: applicationReceipt,
                                token: token
                            )
                        }
                        self.applicationUpdateAdmissionTail = admissionTask
                    },""",
)

replace_once(
    app_path,
    """    private func receivedApplicationUpdate(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) async {""",
    """    private func receivedApplicationUpdate(
        _ update: [String: String],
        receipt: TuyaReadOnlyApplicationReceipt,
        token: TuyaReadOnlyConnectionToken
    ) async {""",
)

replace_once(
    app_path,
    """
        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        // Snapshot the exact account identity""",
    """
        // The synchronous SDK callback already owns the controller-lifetime admission drain.
        // Snapshot the exact account identity""",
)

replace_once(
    app_path,
    "try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)",
    """try await sessionLedger.recordApplicationUpdate(
                isNonEmpty: !update.isEmpty,
                receipt: receipt,
                for: token
            )""",
)

replace_once(
    app_path,
    """                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }

                let now = DispatchTime.now().uptimeNanoseconds""",
    """                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }

                // A callback already delivered by SmartLife owns an opaque package receipt and
                // must enter the ledger before the watchdog is allowed to cross the 60 s cutoff.
                // Do not reset `previousPollUptime`: a stalled drain still invalidates continuity.
                guard self.applicationUpdateAdmissionsInFlight == 0 else {
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }

                let now = DispatchTime.now().uptimeNanoseconds""",
)

app = Path(app_path)
text = app.read_text()
old_callback_type = "onApplicationUpdate: @escaping ([String: String]) -> Void,"
if text.count(old_callback_type) != 2:
    raise SystemExit(
        f"expected two OfficialTuyaDriver callback type declarations, found {text.count(old_callback_type)}"
    )
text = text.replace(
    old_callback_type,
    "onApplicationUpdate: @escaping @MainActor ([String: String]) -> Void,",
)
old_storage = "private var onApplicationUpdate: (([String: String]) -> Void)?"
if text.count(old_storage) != 1:
    raise SystemExit(
        f"expected one SmartLife callback storage declaration, found {text.count(old_storage)}"
    )
text = text.replace(
    old_storage,
    "private var onApplicationUpdate: (@MainActor ([String: String]) -> Void)?",
    1,
)
app.write_text(text)

# Sanity-check the intended authority shape before the workflow commits it.
app_text = app.read_text()
ledger_text = Path(ledger_path).read_text()
assert "let applicationReceipt = TuyaReadOnlyApplicationReceipt.capture(for: token)" in app_text
assert "applicationUpdateAdmissionTail" in app_text
assert "guard self.applicationUpdateAdmissionsInFlight == 0 else {" in app_text
assert "receipt: TuyaReadOnlyApplicationReceipt" in app_text
assert "public struct TuyaReadOnlyApplicationReceipt: Sendable" in ledger_text
assert "receivedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds" in ledger_text
assert "guard receipt.token == token else" in ledger_text
assert "let now = receipt.receivedAtUptimeNanoseconds" in ledger_text

Path(".github/workflows/capture-delivery-cutoff-repair-materializer.yml").unlink()
Path(__file__).unlink()
