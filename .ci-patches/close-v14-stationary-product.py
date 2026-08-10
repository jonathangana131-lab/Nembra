from pathlib import Path
import re

ROOT = Path('.')
APP = Path('NembraApp/App/NembraCaptureEntrypoint.swift')
LEDGER = Path('Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedReadOnlySessionLedger.swift')
TESTS = Path('Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one literal match, found {count}')
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    rx = re.compile(pattern, re.MULTILINE | re.DOTALL)
    found = list(rx.finditer(text))
    if len(found) != 1:
        raise SystemExit(f'{label}: expected one regex match, found {len(found)}')
    return rx.sub(lambda _: replacement, text, count=1)


# ---------------------------------------------------------------------------
# Package: preserve both accepted names for the same clock-independent terminal.
# markInternalLifecycleFailure is the current app-facing semantic; the older
# markChronologyIntegrityInvalidated remains source-compatible for accepted donors.
# ---------------------------------------------------------------------------
ledger = LEDGER.read_text()
ledger = replace_once(
    ledger,
    '    private static let chronologyIntegrityFailureReason =\n        "Read-only session chronology integrity was invalidated."',
    '    private static let chronologyIntegrityFailureReason =\n        "Read-only session chronology integrity was invalidated."\n    private static let internalLifecycleFailureReason =\n        "Session authority was retired after an internal lifecycle or chronology failure."',
    'internal lifecycle failure reason',
)
insert_after = '''    public func markChronologyIntegrityInvalidated(for token: TuyaReadOnlyConnectionToken) throws {
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

        authenticationState = .failed(reason: Self.chronologyIntegrityFailureReason)
        currentToken = nil
    }
'''
replacement = insert_after + '''
    /// Clock-independent fail-closed retirement for the exact current generation when an
    /// internal lifecycle mutation cannot be trusted to take another monotonic receipt.
    /// This is not source drift, disconnect, observation-gap evidence, or SDK failure.
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
'''
ledger = replace_once(ledger, insert_after, replacement, 'internal lifecycle terminal')
LEDGER.write_text(ledger)

# ---------------------------------------------------------------------------
# App: fresh correlation is current-session evidence only; explicit confirmation
# is the promotion boundary; progress is app-published; export carries replayable
# correlation provenance; all clock-broken terminals preserve package/app ownership.
# ---------------------------------------------------------------------------
app = APP.read_text()
app = replace_once(
    app,
    '        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed',
    '        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed',
    'correlated phase',
)

correlation_models = '''    struct CorrelationCandidateExport: Codable {
        let id: String
        let isConnectable: Bool?
    }

    struct CorrelationSnapshotExport: Codable {
        let phase: String
        let observationSeriesIdentity: String
        let windowSequence: UInt64
        let candidates: [CorrelationCandidateExport]
    }

    struct CorrelationWindowExport: Codable {
        let phase: String
        let windowSequence: UInt64
        let startedAtUptimeNanoseconds: UInt64
        let endedAtUptimeNanoseconds: UInt64
        let observedCandidateCount: Int
    }

    struct CorrelationExport: Codable {
        let method: String
        let disposition: String
        let operatorConfirmed: Bool
        let repeatableCandidateIDs: [String]
        let observationSeriesIdentities: [String]
        let windows: [CorrelationWindowExport]
        let snapshots: [CorrelationSnapshotExport]
    }

    struct Export: Codable {'''
app = replace_once(app, '    struct Export: Codable {', correlation_models, 'correlation export models')
app = replace_once(
    app,
    '        let selectedPeripheralID: String?\n        let phase: Phase',
    '        let selectedPeripheralID: String?\n        let targetCorrelationMethod: String?\n        let targetCorrelationWindowCount: Int?\n        let targetCorrelationOperatorConfirmed: Bool\n        let targetCorrelation: CorrelationExport?\n        let phase: Phase',
    'export correlation fields',
)

app = replace_once(
    app,
    '    @Published private(set) var exportData: Data?\n    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"',
    '    @Published private(set) var exportData: Data?\n    @Published private(set) var exportName = "Nembra-Secure-Link-Diagnostics.json"\n    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?',
    'published correlation progress',
)
app = replace_once(
    app,
    '    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var driver: OfficialTuyaDriver?',
    '    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationResult: PassiveBluetoothPowerCycleObservationResult?\n    private var pendingCorrelatedTargetID: UUID?\n    private var targetCorrelationMethod: String?\n    private var targetCorrelationWindowCount: Int?\n    private var targetCorrelationOperatorConfirmed = false\n    private var correlationProgressTask: Task<Void, Never>?\n    private var driver: OfficialTuyaDriver?',
    'correlation controller state',
)
app = replace_once(
    app,
    '    deinit { watchdog?.cancel() }',
    '    deinit {\n        watchdog?.cancel()\n        correlationProgressTask?.cancel()\n    }',
    'deinit progress retirement',
)
app = replace_once(
    app,
    '    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }',
    '    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }',
    'published progress projection',
)

# Start each package window and immediately bridge its asynchronous readiness into @Published state.
app = replace_once(
    app,
    '            try session.startCurrentWindow()\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline',
    '            try session.startCurrentWindow()\n            startCorrelationProgressObservation(session: session)\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline',
    'start progress observer',
)

# A successfully sealed window retires its observer. Early seal attempts keep observing.
app = replace_once(
    app,
    '            let final = try session.finishCurrentWindow()\n            if let final {',
    '            let final = try session.finishCurrentWindow()\n            stopCorrelationProgressObservation()\n            if let final {',
    'stop progress after successful window seal',
)
app = replace_once(
    app,
    '            default:\n                session.abandonCurrentWindow()\n                correlationSession = nil',
    '            default:\n                stopCorrelationProgressObservation()\n                session.abandonCurrentWindow()\n                correlationSession = nil',
    'stop progress on typed terminal',
)
app = replace_once(
    app,
    '        } catch {\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally("\\(sealedLabel) failed closed:',
    '        } catch {\n            stopCorrelationProgressObservation()\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally("\\(sealedLabel) failed closed:',
    'stop progress on untyped terminal',
)

finish_replacement = '''    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {
        stopCorrelationProgressObservation()
        correlationResult = result
        correlationSession = nil
        targetCorrelationMethod = "package-owned-fresh-manager-off1-on1-off2-on2"
        targetCorrelationWindowCount = result.windows.count
        targetCorrelationOperatorConfirmed = false

        switch result.correlation.disposition {
        case let .singleRepeatableCandidate(id):
            let historicalCaptureID = id == Self.historicalCapturePeripheral
            var evidence = ["fresh OFF1→ON1→OFF2→ON2 full-UUID correlation"]
            if historicalCaptureID {
                evidence.append("matches C7D09A22 capture-local UUID descriptive")
            }
            let candidate = Candidate(
                id: id,
                name: nil,
                rssi: nil,
                advertisements: nil,
                newAfterPowerOn: true,
                fd50: false,
                tuyaCompany: false,
                historicalCaptureID: historicalCaptureID,
                freshlyCorrelated: true,
                expectedName: false,
                score: 0,
                evidence: evidence
            )
            byID = [id: candidate]
            candidates = [candidate]
            pendingCorrelatedTargetID = id
            selectedID = nil
            phase = .correlated
            message = "One full CoreBluetooth UUID repeated the complete fresh correlation series. Confirm this correlated Bluetooth target explicitly before authentication. This is current-session correlation evidence, not permanent scooter identity."
            log("target_correlation_ready_for_confirmation", [
                "id": id.uuidString,
                "authority": "fresh-repeated-off-on-full-corebluetooth-id",
                "historicalCaptureUUIDMatch": String(historicalCaptureID),
                "windows": String(result.windows.count)
            ])

        case let .ambiguousRepeatableCandidates(ids):
            pendingCorrelatedTargetID = nil
            failLocally("Fresh correlation remained ambiguous across \(ids.count) repeatable full UUIDs. Do not guess from name, RSSI, FD50, Tuya hints, or the historical capture UUID; restart from OFF1 after reducing nearby-device ambiguity.", "target_correlation_ambiguous")

        case .noRepeatableCandidate:
            pendingCorrelatedTargetID = nil
            failLocally("No full UUID repeated the required OFF1→ON1→OFF2→ON2 pattern. Do not fall back to the historical capture UUID; restart the fresh correlation series.", "target_correlation_no_repeatable_candidate")

        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            pendingCorrelatedTargetID = nil
            failLocally("The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.", "target_correlation_provenance_rejected")
        }
    }

    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            message = "A fresh correlated Bluetooth target must be available before confirmation."
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Current Tuya account/device authority changed before correlated-target confirmation.", "sdk_authority_changed_before_target_confirmation")
            return
        }

        selectedID = id
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. Correlation scanning is retired before Tuya's SDK takes BLE ownership. This does not create permanent scooter identity."
        log("candidate_selected", [
            "id": id.uuidString,
            "authority": "operator-confirmed-fresh-power-cycle-correlation",
            "correlation": "OFF1-ON1-OFF2-ON2",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }

    func invalidateSDKMembership() {'''
app = sub_once(
    app,
    r'    private func finishCorrelationSeries\(_ result: PassiveBluetoothPowerCycleObservationResult\) \{.*?^    func invalidateSDKMembership\(\) \{',
    finish_replacement,
    'explicit target confirmation boundary',
)

# Source authority loss revokes the recipe-order promotion, not merely the SDK membership flag.
app = replace_once(
    app,
    '        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }',
    '        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            stopCorrelationProgressObservation()\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        pendingCorrelatedTargetID = nil\n        selectedID = nil\n        targetCorrelationOperatorConfirmed = false',
    'membership revokes target promotion',
)
app = replace_once(
    app,
    '        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {',
    '        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {',
    'membership correlated phase terminal',
)

# Mint app ownership before the auth-start mutation so any chronology rejection can retire exact package authority.
app = replace_once(
    app,
    '''                let token = try await self.sessionLedger.beginConnection()
                try await self.sessionLedger.markAuthenticationStarted(for: token)
                self.currentConnectionToken = token
                await self.refreshLedgerSnapshot()''',
    '''                let token = try await self.sessionLedger.beginConnection()
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication-start chronology failed closed before Tuya BLE ownership: \(error.localizedDescription)",
                        kind: "session_auth_start_chronology_rejected"
                    )
                    return
                }
                await self.refreshLedgerSnapshot()''',
    'auth-start exact token ownership',
)

app = replace_once(
    app,
    '''                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }''',
    '''                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }''',
    'auth promotion internal lifecycle terminal',
)
app = replace_once(
    app,
    '''            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )''',
    '''            case .invalidClock:
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )''',
    'settlement invalid clock terminal',
)

# A current SDK failure may arrive after account/device source authority has already drifted.
auth_failure = '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before the SDK failure callback was classified.",
                kind: "sdk_source_authority_lost_before_auth_failure"
            )
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }

    private func authenticationAcquisitionFailed'''
app = sub_once(
    app,
    r'    private func authenticationFailed\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func authenticationAcquisitionFailed',
    auth_failure,
    'authentication failure source race',
)

# Ordinary auth/acquisition failure samples the clock once; if that fails, switch to the no-clock terminal.
app = replace_once(
    app,
    '''        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markAuthenticationFailed(for: token)
        currentConnectionToken = nil''',
    '''        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch {
            await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_terminal_rejected")
            return
        }
        currentConnectionToken = nil''',
    'auth failure no swallowed terminal',
)

# Package record mutation: distinguish already-retired continuity, broken-clock internal lifecycle, and other continuity failures.
app = replace_once(
    app,
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }''',
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await retireAppOwnershipAfterLedgerTerminal(
                token: token,
                message: "Application chronology detected an invalid observation gap.",
                kind: "application_observation_continuity_invalidated"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application chronology failed closed because the monotonic clock regressed.",
                kind: "application_update_clock_regressed"
            )
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }''',
    'application update terminals',
)

# Watchdog terminal classification.
app = sub_once(
    app,
    r'''                guard now >= previousPollUptime else \{.*?                    return
                \}''',
    '''                guard now >= previousPollUptime else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated observation chronology was invalidated by a monotonic-clock regression.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }''',
    'watchdog local clock regression',
)
app = sub_once(
    app,
    r'''                guard gap <= Self\.maximumObservationPollGapNanoseconds else \{.*?                    return
                \}''',
    '''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }''',
    'watchdog gap helper',
)
app = replace_once(
    app,
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateObservationContinuity(''',
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.retireAppOwnershipAfterLedgerTerminal(
                        token: token,
                        message: "Authenticated-session liveness detected an invalid observation gap.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed because the monotonic clock regressed.",
                        kind: "session_liveness_clock_regressed"
                    )
                    return
                } catch {
                    await self.invalidateObservationContinuity(''',
    'watchdog package mutation terminals',
)
app = replace_once(
    app,
    '''                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }''',
    '''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                        await self.retireAppOwnershipAfterLedgerTerminal(
                            token: token,
                            message: "Canonical readiness could not be sealed because observation continuity was already invalidated.",
                            kind: "accepted_prefix_seal_continuity_invalidated"
                        )
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness could not be sealed because the monotonic clock regressed.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }''',
    'seal terminal classification',
)

# No-application deadline may itself fail to sample the terminal boundary.
app = replace_once(
    app,
    '''                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    self.sdkLocalBLEOnline = false''',
    '''                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Application-observation deadline could not be sealed because the monotonic clock regressed.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Application-observation deadline terminal was rejected: \(error.localizedDescription)",
                            kind: "application_timeout_terminal_rejected"
                        )
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false''',
    'application deadline terminal',
)

# Replace terminal helper block with exact, non-swallowing ownership transitions.
helpers = '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Observed local-BLE loss could not seal its chronology because the monotonic clock regressed.",
                kind: "sdk_local_ble_drop_clock_regressed"
            )
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(
                token: token,
                message: "The local-BLE session ended after ledger authority had already retired.",
                kind: "sdk_local_ble_dropped_after_ledger_terminal"
            )
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Observed local-BLE loss could not retire the current generation: \(error.localizedDescription)",
                kind: "sdk_local_ble_drop_terminal_rejected"
            )
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture."
        log("sdk_local_ble_dropped", ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateSourceAuthority(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_clock_regressed")
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_after_ledger_terminal")
            return
        } catch {
            await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_terminal_rejected")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_clock_regressed")
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_after_ledger_terminal")
            return
        } catch {
            await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_terminal_rejected")
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func invalidateInternalLifecycle(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_already_retired")
            return
        } catch {
            // Do not clear app ownership after a rejected package terminal. Keeping the exact token
            // visible is safer than creating hidden package authority; the UI remains failed/blocked.
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = "\(message) Exact generation retirement was rejected; relaunch Capture before another attempt."
            log("\(kind)_retirement_rejected", ["generation": String(token.diagnosticGeneration)])
            return
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func retireAppOwnershipAfterLedgerTerminal(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func refreshLedgerSnapshot() async {'''
app = sub_once(
    app,
    r'    private func recordObservedTransportLoss\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func refreshLedgerSnapshot\(\) async \{',
    helpers,
    'terminal helper ownership alignment',
)

# Structured replayable correlation export plus the simple contract fields used by earlier red tests.
export_helpers = '''    private static func correlationPhaseLabel(_ phase: PassiveBluetoothPowerCycleObservationPhase) -> String {
        switch phase {
        case .firstPoweredOff: return "OFF1"
        case .firstPoweredOn: return "ON1"
        case .secondPoweredOff: return "OFF2"
        case .secondPoweredOn: return "ON2"
        }
    }

    private static func correlationDispositionLabel(_ disposition: PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition) -> String {
        switch disposition {
        case .invalidObservationAuthority: return "invalid-observation-authority"
        case .invalidObservationWindowOrder: return "invalid-observation-window-order"
        case .noRepeatableCandidate: return "no-repeatable-candidate"
        case .ambiguousRepeatableCandidates: return "ambiguous-repeatable-candidates"
        case .singleRepeatableCandidate: return "single-repeatable-candidate"
        }
    }

    private func makeCorrelationExport() -> CorrelationExport? {
        guard let result = correlationResult else { return nil }
        let windows = result.windows.map { receipt in
            CorrelationWindowExport(
                phase: Self.correlationPhaseLabel(receipt.phase),
                windowSequence: receipt.windowSequence.rawValue,
                startedAtUptimeNanoseconds: receipt.startedAtUptimeNanoseconds,
                endedAtUptimeNanoseconds: receipt.endedAtUptimeNanoseconds,
                observedCandidateCount: receipt.observedCandidateCount
            )
        }
        let phaseLabels = ["OFF1", "ON1", "OFF2", "ON2"]
        let snapshots = result.observationSnapshots.enumerated().map { pair in
            let index = pair.offset
            let snapshot = pair.element
            return CorrelationSnapshotExport(
                phase: index < phaseLabels.count ? phaseLabels[index] : "UNKNOWN",
                observationSeriesIdentity: snapshot.observationSeriesIdentity.rawValue.uuidString,
                windowSequence: snapshot.windowSequence.rawValue,
                candidates: snapshot.candidates.map {
                    CorrelationCandidateExport(id: $0.id.uuidString, isConnectable: $0.isConnectable)
                }
            )
        }
        return CorrelationExport(
            method: targetCorrelationMethod ?? "package-owned-fresh-manager-off1-on1-off2-on2",
            disposition: Self.correlationDispositionLabel(result.correlation.disposition),
            operatorConfirmed: targetCorrelationOperatorConfirmed,
            repeatableCandidateIDs: result.correlation.repeatableCandidateIdentifiers.map { $0.uuidString },
            observationSeriesIdentities: result.correlation.observationSeriesIdentities.map { $0.rawValue.uuidString },
            windows: windows,
            snapshots: snapshots
        )
    }

    func prepareExport() {'''
app = replace_once(app, '    func prepareExport() {', export_helpers, 'correlation export helpers')
app = replace_once(app, '            schemaVersion: 7,', '            schemaVersion: 8,', 'schema version')
app = replace_once(
    app,
    '            selectedPeripheralID: selectedID?.uuidString,\n            phase: phase,',
    '            selectedPeripheralID: selectedID?.uuidString,\n            targetCorrelationMethod: targetCorrelationMethod,\n            targetCorrelationWindowCount: targetCorrelationWindowCount,\n            targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed,\n            targetCorrelation: makeCorrelationExport(),\n            phase: phase,',
    'prepared export correlation fields',
)

# Progress observer is presentation-only and cannot mutate evidence authority.
progress_helpers = '''    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {
        stopCorrelationProgressObservation()
        correlationProgress = session.progress
        correlationProgressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let progress = session.progress
                self.correlationProgress = progress
                guard let progress, !progress.isSeriesInvalidated else { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopCorrelationProgressObservation() {
        correlationProgressTask?.cancel()
        correlationProgressTask = nil
    }

    private func resetDiscoverySessionOnly() {'''
app = replace_once(app, '    private func resetDiscoverySessionOnly() {', progress_helpers, 'progress observer helpers')
app = replace_once(
    app,
    '''    private func resetDiscoverySessionOnly() {
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        central.stopScan()''',
    '''    private func resetDiscoverySessionOnly() {
        stopCorrelationProgressObservation()
        correlationProgress = nil
        correlationSession?.abandonCurrentWindow()
        correlationSession = nil
        correlationResult = nil
        pendingCorrelatedTargetID = nil
        targetCorrelationMethod = nil
        targetCorrelationWindowCount = nil
        targetCorrelationOperatorConfirmed = false
        central.stopScan()''',
    'reset correlation authority and presentation',
)
app = replace_once(
    app,
    '''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }''',
    '''    private func failLocally(_ text: String, _ kind: String) {
        if phase == .baseline || phase == .powerOn || phase == .scanning {
            stopCorrelationProgressObservation()
            correlationProgress = nil
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
        }''',
    'fail local progress retirement',
)

# Primary UI: exact build authority, published scan liveness, explicit target confirmation.
app = replace_once(
    app,
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? test.fieldBuildIdentifier : "Not authoritative")',
    'field build UI source',
)
app = replace_once(
    app,
    '            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {',
    '            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {',
    'field build no-go banner',
)
app = replace_once(
    app,
    '                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)',
    '                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)',
    'field build start action',
)
app = replace_once(
    app,
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            default:''',
    '''            case .powerOn:
                Text("Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)")
                    .foregroundStyle(.secondary)
                Button("Start \\(test.correlationWindowLabel) window") { test.startNextCorrelationWindow() }
                    .buttonStyle(.borderedProminent)

            case .correlated:
                Text("Correlation found one repeatable full UUID. Confirm it only as this attempt's correlated Bluetooth target.")
                    .foregroundStyle(.secondary)
                Button("Confirm correlated Bluetooth target") { test.confirmCorrelatedTarget() }
                    .buttonStyle(.borderedProminent)

            default:''',
    'explicit target confirmation UI',
)
app = replace_once(
    app,
    '            Text("Export includes exact build identity, current-session correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.',
    '            Text("Export includes exact build identity, current-session OFF1→ON1→OFF2→ON2 correlation windows/catalogs + explicit-confirmation state, correlated target ID, SDK membership state, canonical generation/chronology, local-BLE status, terminal state, and opaque application-value projections.',
    'export UI provenance copy',
)
APP.write_text(app)

# ---------------------------------------------------------------------------
# Tests: absorb current red contracts and repair stale/contradictory source assertions.
# ---------------------------------------------------------------------------
explicit = (TESTS / 'TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift').read_text()
explicit = replace_once(
    explicit,
    '            to: "func invalidateSDKMembership"\n        )\n\n        #expect(finish.contains("singleRepeatableCandidate"))',
    '            to: "func confirmCorrelatedTarget"\n        )\n\n        #expect(finish.contains("singleRepeatableCandidate"))',
    'explicit confirmation section boundary',
)
(TESTS / 'TuyaExplicitCorrelatedTargetConfirmationSourceTests.swift').write_text(explicit)

fresh = (TESTS / 'TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift').read_text()
fresh = replace_once(
    fresh,
    '        #expect(invalidClockBranch.contains("authenticationAcquisitionFailed"))\n        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))\n        #expect(!invalidClockBranch.contains("invalidateSourceAuthority"))',
    '        #expect(invalidClockBranch.contains("invalidateInternalLifecycle"))\n        #expect(!invalidClockBranch.contains("authenticationAcquisitionFailed"))\n        #expect(!timeoutBranch.contains("invalidateSourceAuthority"))\n        #expect(!invalidClockBranch.contains("invalidateSourceAuthority"))\n        #expect(app.contains("sessionLedger.markInternalLifecycleFailure(for: token)"))',
    'fresh-target invalid clock contract',
)
(TESTS / 'TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift').write_text(fresh)

transport = (TESTS / 'TuyaTransportSuccessAuthoritySourceTests.swift').read_text()
transport = replace_once(
    transport,
    '@Test("duplicate success callbacks share one local-BLE settlement owner and auth rejection retires authority")',
    '@Test("duplicate success callbacks share one local-BLE settlement owner and auth rejection retires internal lifecycle authority")',
    'transport test title',
)
transport = replace_once(
    transport,
    '            Issue.record("Authentication chronology rejection needs a terminal source-authority route.")',
    '            Issue.record("Authentication chronology rejection needs the clock-independent internal-lifecycle terminal.")',
    'transport issue copy',
)
transport = replace_once(
    transport,
    '        #expect(prefix.contains("invalidateSourceAuthority"))',
    '        #expect(prefix.contains("invalidateInternalLifecycle"))\n        #expect(!prefix.contains("invalidateSourceAuthority"))',
    'transport auth rejection terminal',
)
(TESTS / 'TuyaTransportSuccessAuthoritySourceTests.swift').write_text(transport)

final = (TESTS / 'TuyaFieldFinalAuthoritySourceTests.swift').read_text()
final = sub_once(
    final,
    r'''        let start = try section\(in: source, from: "func startBaseline\(\)", to: "private func beginBaselineScan\(\)"\).*?        #expect\(begin\.contains\("scanForPeripherals"\)\)''',
    '''        let start = try section(in: source, from: "func startBaseline()", to: "private func beginCorrelationSeries()")
        let begin = try section(in: source, from: "private func beginCorrelationSeries()", to: "func startNextCorrelationWindow()")

        #expect(start.contains("guard privateConfig, sdkAccountLoggedIn"))
        #expect(start.contains("verifySDKMembership"))
        #expect(start.contains("beginCorrelationSeries()"))
        #expect(begin.contains("sdkAccountLoggedIn"))
        #expect(begin.contains("sdkDeviceMembershipVerified"))
        #expect(begin.contains("PassiveBluetoothPowerCycleObservationSession(minimumWindowDuration: 10)"))
        #expect(begin.contains("startCurrentCorrelationWindow"))''',
    'final authority correlation producer',
)
final = sub_once(
    final,
    r'''    @Test\("only the accepted prior physical identity can authorize a local candidate"\).*?^    @Test\("login success re-reads SDK authority and account errors redact the submitted identifier"\)''',
    '''    @Test("only fresh repeated correlation plus explicit operator confirmation can authorize a local candidate")
    func descriptiveRadioHintsCannotAuthorizeTarget() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(source.contains("var likely: Bool { freshlyCorrelated }"))
        #expect(source.contains("historicalCapturePeripheral"))
        #expect(source.contains("matches C7D09A22 capture-local UUID descriptive"))
        #expect(source.contains("case let .singleRepeatableCandidate(id):"))
        #expect(source.contains("func confirmCorrelatedTarget"))
        #expect(source.contains("operator-confirmed-fresh-power-cycle-correlation"))
        #expect(!source.contains("var likely: Bool { knownID }"))
        #expect(!source.contains("accepted-prior-physical-corebluetooth-uuid"))
        #expect(!source.contains("fd50 && tuyaCompany"))
    }

    @Test("login success re-reads SDK authority and account errors redact the submitted identifier")''',
    'final authority target truth',
)
(TESTS / 'TuyaFieldFinalAuthoritySourceTests.swift').write_text(final)

# Presentation-progress red contract from #2124, now product-consumed on this successor.
(TESTS / 'TuyaCorrelationProgressPresentationSourceTests.swift').write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture correlation-progress presentation bridge")
struct TuyaCorrelationProgressPresentationSourceTests {
    @Test("package scan-readiness progress is published instead of pulled from an unobservable session")
    func correlationProgressHasAppOwnedPublishedSnapshot() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(app.contains("@Published private(set) var correlationProgress"))
        #expect(!app.contains("var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }"))
        #expect(app.contains("private var correlationProgressTask: Task<Void, Never>?"))
        let live = try section(in: app, from: "var correlationWindowIsScanning", to: "var correlationWindowLabel")
        #expect(live.contains("correlationProgress?.isScanning == true"))
        #expect(!live.contains("correlationSession?.progress"))
    }

    @Test("starting a window bridges asynchronous package readiness into the controller")
    func startWindowStartsPresentationObservation() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let start = try section(in: app, from: "private func startCurrentCorrelationWindow()", to: "func finishCorrelationWindow()")
        #expect(start.contains("session.startCurrentWindow()"))
        #expect(start.contains("startCorrelationProgressObservation(session:"))
        let observer = try section(in: app, from: "private func startCorrelationProgressObservation", to: "private func stopCorrelationProgressObservation")
        #expect(observer.contains("session.progress"))
        #expect(observer.contains("self.correlationProgress = progress"))
        #expect(observer.contains("Task.sleep"))
        #expect(observer.contains("Task.isCancelled"))
    }

    @Test("presentation observer is retired at window or attempt boundaries")
    func progressObserverCannotLeakAcrossWindowsOrAttempts() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let finish = try section(in: app, from: "func finishCorrelationWindow()", to: "private func finishCorrelationSeries")
        #expect(finish.contains("stopCorrelationProgressObservation"))
        let reset = try section(in: app, from: "private func resetDiscoverySessionOnly", to: "private func failLocally")
        #expect(reset.contains("stopCorrelationProgressObservation"))
        #expect(reset.contains("correlationProgress = nil"))
        let stop = try section(in: app, from: "private func stopCorrelationProgressObservation", to: "private func")
        #expect(stop.contains("correlationProgressTask?.cancel()"))
        #expect(stop.contains("correlationProgressTask = nil"))
    }

    @Test("primary seal affordance remains gated by published package scan liveness")
    func sealActionUsesPublishedLiveness() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = try section(in: app, from: "private struct SecureLinkView", to: "#Preview")
        #expect(view.contains("test.correlationWindowIsScanning"))
        #expect(view.contains(".disabled(!test.correlationWindowIsScanning)"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
''')

# Functional proof for the app-facing no-clock terminal, from accepted donor #2107 semantics.
(TESTS / 'TuyaInternalLifecycleFailureTerminalTests.swift').write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya internal lifecycle failure terminal")
struct TuyaInternalLifecycleFailureTerminalTests {
    @Test("clock-regressed auth promotion can retire exact generation without another clock sample")
    func regressedAuthenticationPromotionRetiresWithoutClockRecovery() async throws {
        let clock = InternalLifecycleFailureClock(100)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(150)
        try await ledger.markAuthenticationStarted(for: token)
        let before = await ledger.currentPreflightSnapshot()
        clock.set(149)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
        #expect(failed.authenticationMethod == nil)
        #expect(failed.authenticatedAtUptimeNanoseconds == nil)
        #expect(failed.applicationPayloadCount == 0)
        #expect(failed.latestObservedUptimeNanoseconds == before.latestObservedUptimeNanoseconds)
        clock.set(200)
        await #expect(throws: TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection) {
            try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        }
    }

    @Test("post-auth internal failure preserves earned evidence only diagnostically")
    func postAuthenticationFailurePreservesEarnedChronology() async throws {
        let clock = InternalLifecycleFailureClock(1_000)
        let ledger = TuyaAuthenticatedReadOnlySessionLedger(nowUptimeNanoseconds: clock.now)
        let token = try await ledger.beginConnection()
        clock.set(1_500)
        try await ledger.markAuthenticationStarted(for: token)
        clock.set(2_000)
        try await ledger.markAuthenticated(for: token, method: .smartLifeAppSDK)
        clock.set(2_500)
        try await ledger.recordApplicationUpdate(isNonEmpty: true, for: token)
        let earned = await ledger.currentPreflightSnapshot()
        clock.set(1)
        try await ledger.markInternalLifecycleFailure(for: token)
        let failed = await ledger.currentPreflightSnapshot()
        #expect(failed.authenticationState == .failed(reason: "Session authority was retired after an internal lifecycle or chronology failure."))
        #expect(failed.authenticationMethod == earned.authenticationMethod)
        #expect(failed.authenticatedAtUptimeNanoseconds == earned.authenticatedAtUptimeNanoseconds)
        #expect(failed.applicationPayloadCount == earned.applicationPayloadCount)
        #expect(failed.latestApplicationPayloadUptimeNanoseconds == earned.latestApplicationPayloadUptimeNanoseconds)
        #expect(failed.latestObservedUptimeNanoseconds == earned.latestObservedUptimeNanoseconds)
    }
}

private final class InternalLifecycleFailureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64
    init(_ value: UInt64) { self.value = value }
    var now: @Sendable () -> UInt64 {
        { [self] in lock.lock(); defer { lock.unlock() }; return value }
    }
    func set(_ newValue: UInt64) { lock.lock(); value = newValue; lock.unlock() }
}
''')

# Tighten the source red contract to the product's now-consumed terminal markers.
session = (TESTS / 'TuyaSessionTerminalRetirementSourceTests.swift').read_text()
# This file already expects invalidateInternalLifecycle + markInternalLifecycleFailure. Keep it intact.
(TESTS / 'TuyaSessionTerminalRetirementSourceTests.swift').write_text(session)

# Mechanical invariants. Fail the patch job before committing if any stale authority survives.
final_app = APP.read_text()
for forbidden in (
    'var likely: Bool { knownID }',
    'accepted-prior-physical-corebluetooth-uuid',
    'try? await sessionLedger.markAuthenticationFailed(for: token)',
    'try? await sessionLedger.markSourceAuthorityInvalidated(for: token)',
    'try? await sessionLedger.markObservationContinuityInvalidated(for: token)',
    'try? await sessionLedger.endConnection(for: token)',
):
    if forbidden in final_app:
        raise SystemExit(f'stale/fail-open authority remains: {forbidden}')
for required in (
    '@Published private(set) var correlationProgress',
    'func confirmCorrelatedTarget()',
    'targetCorrelationOperatorConfirmed = true',
    'targetCorrelation: CorrelationExport?',
    'var fieldBuildIsAuthoritative: Bool',
    'private func invalidateInternalLifecycle(',
    'sessionLedger.markInternalLifecycleFailure(for: token)',
    'private var localBLESettlementToken: TuyaReadOnlyConnectionToken?',
    'session_auth_start_chronology_rejected',
    'application_update_clock_regressed',
):
    if required not in final_app:
        raise SystemExit(f'required closure marker missing: {required}')
if 'public func markInternalLifecycleFailure' not in LEDGER.read_text():
    raise SystemExit('package internal-lifecycle terminal missing')

print('V14 stationary Capture product closure applied deterministically')
