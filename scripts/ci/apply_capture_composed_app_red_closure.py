#!/usr/bin/env python3
from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
PROVENANCE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCorrelatedTargetExportProvenanceSourceTests.swift")
RESUME_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaAuthenticationPromotionResumeFenceSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def remove_exact_count(text: str, needle: str, expected: int, label: str) -> str:
    count = text.count(needle)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} matches, found {count}")
    return text.replace(needle, "")


source = APP.read_text()

# Package-owned PassiveBluetoothPowerCycleObservationSession is the only discovery owner.
source = replace_once(source, "@preconcurrency import CoreBluetooth\n", "", "retire app CoreBluetooth import")
source = replace_once(source, "\nlet CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n", "\n", "retire connectable-key alias")
source = replace_once(
    source,
    """        case idle, baseline, powerOn, scanning, selected, authenticating, observing, accepted, failed\n""",
    """        case idle, baseline, powerOn, scanning, correlated, selected, authenticating, observing, accepted, failed\n""",
    "explicit correlation phase",
)
source = replace_once(source, "    static let fd50 = CBUUID(string: \"FD50\")\n", "", "retire app FD50 scanner constant")
source = replace_once(
    source,
    """    @Published private(set) var candidates: [Candidate] = []\n    @Published private(set) var selectedID: UUID?\n""",
    """    @Published private(set) var candidates: [Candidate] = []\n    @Published private(set) var correlationProgress: PassiveBluetoothPowerCycleObservationProgress?\n    @Published private(set) var selectedID: UUID?\n""",
    "publish package correlation progress",
)
source = replace_once(source, "    private var central: CBCentralManager!\n", "", "retire app central manager")
source = replace_once(
    source,
    """    private var byID: [UUID: Candidate] = [:]\n    private var baseline = Set<UUID>()\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n""",
    """    private var byID: [UUID: Candidate] = [:]\n    private var pendingCorrelatedID: UUID?\n    private var correlationSession: PassiveBluetoothPowerCycleObservationSession?\n    private var correlationProgressTask: Task<Void, Never>?\n""",
    "correlation state ownership",
)
source = replace_once(source, "        central = CBCentralManager(delegate: self, queue: .main)\n", "", "retire app central construction")
source = replace_once(
    source,
    """    deinit { watchdog?.cancel() }\n\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n""",
    """    deinit {\n        watchdog?.cancel()\n        correlationProgressTask?.cancel()\n    }\n\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n""",
    "retire presentation task on deinit",
)
source = replace_once(
    source,
    """    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }\n    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationProgress: PassiveBluetoothPowerCycleObservationProgress? { correlationSession?.progress }\n    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }\n""",
    """    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }\n    var currentAccountUID: String? { OfficialTuyaFactory.currentAccountUID }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }\n    var fieldBuildBlocker: String? { buildIdentity.blocker }\n    var selected: Candidate? { selectedID.flatMap { byID[$0] } }\n    var pendingCorrelatedCandidate: Candidate? { pendingCorrelatedID.flatMap { byID[$0] } }\n    var applicationUpdateCount: Int { ledgerSnapshot.applicationPayloadCount }\n    var correlationWindowIsScanning: Bool { correlationProgress?.isScanning == true }\n""",
    "build authority + published correlation projections",
)

# Bridge package readiness/candidate-count presentation into ObservableObject state.
source = replace_once(
    source,
    """        let label = correlationWindowLabel\n        do {\n            try session.startCurrentWindow()\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n""",
    """        let label = correlationWindowLabel\n        do {\n            try session.startCurrentWindow()\n            correlationProgress = session.progress\n            startCorrelationProgressObservation(session: session)\n            phase = progress.phase.operatorExpectedPowerOn ? .scanning : .baseline\n""",
    "start progress bridge with package window",
)
source = replace_once(
    source,
    """        } catch {\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"The \\(label) correlation window failed closed: \\(error.localizedDescription). Restart from OFF1.\", \"target_correlation_window_start_failed\")\n        }\n    }\n\n    func finishCorrelationWindow() {\n""",
    """        } catch {\n            stopCorrelationProgressObservation()\n            correlationProgress = nil\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"The \\(label) correlation window failed closed: \\(error.localizedDescription). Restart from OFF1.\", \"target_correlation_window_start_failed\")\n        }\n    }\n\n    private func startCorrelationProgressObservation(session: PassiveBluetoothPowerCycleObservationSession) {\n        stopCorrelationProgressObservation()\n        correlationProgress = session.progress\n        correlationProgressTask = Task { @MainActor [weak self, weak session] in\n            while !Task.isCancelled {\n                guard let self,\n                      let session,\n                      self.correlationSession === session else { return }\n                let progress = session.progress\n                self.correlationProgress = progress\n                try? await Task.sleep(for: .milliseconds(100))\n            }\n        }\n    }\n\n    private func stopCorrelationProgressObservation() {\n        correlationProgressTask?.cancel()\n        correlationProgressTask = nil\n    }\n\n    func finishCorrelationWindow() {\n""",
    "insert progress observation bridge",
)
source = replace_once(
    source,
    """    func finishCorrelationWindow() {\n        guard phase == .baseline || phase == .scanning,\n              let session = correlationSession else { return }\n        guard sdkAccountLoggedIn,\n""",
    """    func finishCorrelationWindow() {\n        guard phase == .baseline || phase == .scanning,\n              let session = correlationSession else { return }\n        stopCorrelationProgressObservation()\n        guard sdkAccountLoggedIn,\n""",
    "stop progress observer before sealing",
)
source = replace_once(
    source,
    """            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"SDK account/device authority changed during Bluetooth correlation. Restart from OFF1 after re-verifying membership.\", \"sdk_authority_changed_during_target_correlation\")\n""",
    """            correlationProgress = nil\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"SDK account/device authority changed during Bluetooth correlation. Restart from OFF1 after re-verifying membership.\", \"sdk_authority_changed_during_target_correlation\")\n""",
    "clear progress on correlation source drift",
)
source = replace_once(
    source,
    """            phase = .powerOn\n            message = \"\\(sealedLabel) sealed. \\(correlationWindowInstruction) When the scooter has settled, start \\(correlationWindowLabel).\"\n""",
    """            correlationProgress = session.progress\n            phase = .powerOn\n            message = \"\\(sealedLabel) sealed. \\(correlationWindowInstruction) When the scooter has settled, start \\(correlationWindowLabel).\"\n""",
    "publish next correlation phase after seal",
)
source = replace_once(
    source,
    """            case .minimumWindowDurationNotReached:\n                message = \"Keep \\(sealedLabel) unchanged a little longer. The package has not yet earned the required 10 receipt-bounded seconds.\"\n            case .scanReadinessPending:\n                message = \"\\(sealedLabel) is still waiting for confirmed CoreBluetooth scan liveness. Do not advance the physical state yet.\"\n            default:\n                session.abandonCurrentWindow()\n                correlationSession = nil\n""",
    """            case .minimumWindowDurationNotReached:\n                startCorrelationProgressObservation(session: session)\n                message = \"Keep \\(sealedLabel) unchanged a little longer. The package has not yet earned the required 10 receipt-bounded seconds.\"\n            case .scanReadinessPending:\n                startCorrelationProgressObservation(session: session)\n                message = \"\\(sealedLabel) is still waiting for confirmed CoreBluetooth scan liveness. Do not advance the physical state yet.\"\n            default:\n                correlationProgress = nil\n                session.abandonCurrentWindow()\n                correlationSession = nil\n""",
    "resume progress bridge after recoverable early seal",
)
source = replace_once(
    source,
    """        } catch {\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n        }\n    }\n\n    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n""",
    """        } catch {\n            correlationProgress = nil\n            session.abandonCurrentWindow()\n            correlationSession = nil\n            failLocally(\"\\(sealedLabel) failed closed: \\(error.localizedDescription). Restart the complete correlation series.\", \"target_correlation_window_failed\")\n        }\n    }\n\n    private func finishCorrelationSeries(_ result: PassiveBluetoothPowerCycleObservationResult) {\n        stopCorrelationProgressObservation()\n        correlationProgress = nil\n""",
    "retire progress bridge at completed series",
)

# A unique correlation is pending evidence until the operator explicitly confirms it.
source = replace_once(
    source,
    """            byID = [id: candidate]\n            candidates = [candidate]\n            selectedID = id\n            correlationSession = nil\n            phase = .selected\n            message = \"Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Discovery is retired before Tuya's SDK takes BLE ownership.\"\n            log(\"candidate_selected\", [\n                \"id\": id.uuidString,\n                \"authority\": \"fresh-repeated-off-on-full-corebluetooth-id\",\n                \"historicalCaptureUUIDMatch\": String(historicalCaptureID),\n                \"windows\": String(result.windows.count)\n            ])\n""",
    """            byID = [id: candidate]\n            candidates = [candidate]\n            pendingCorrelatedID = id\n            selectedID = nil\n            correlationSession = nil\n            phase = .correlated\n            message = \"Fresh repeated power-cycle correlation found one full CoreBluetooth target. This is current-session correlation evidence, not permanent scooter identity. Confirm the correlated target explicitly before Tuya's SDK may take BLE ownership.\"\n            log(\"candidate_correlated\", [\n                \"id\": id.uuidString,\n                \"authority\": \"fresh-repeated-off-on-full-corebluetooth-id-awaiting-operator-confirmation\",\n                \"historicalCaptureUUIDMatch\": String(historicalCaptureID),\n                \"windows\": String(result.windows.count)\n            ])\n""",
    "do not auto-select unique correlation",
)
source = replace_once(
    source,
    """        case .invalidObservationAuthority, .invalidObservationWindowOrder:\n            correlationSession = nil\n            failLocally(\"The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.\", \"target_correlation_provenance_rejected\")\n        }\n    }\n\n    func invalidateSDKMembership() {\n""",
    """        case .invalidObservationAuthority, .invalidObservationWindowOrder:\n            correlationSession = nil\n            failLocally(\"The package rejected correlation provenance/chronology. Restart from OFF1; prior windows cannot be spliced into a new attempt.\", \"target_correlation_provenance_rejected\")\n        }\n    }\n\n    func confirmCorrelatedTarget() {\n        guard phase == .correlated,\n              let id = pendingCorrelatedID,\n              let candidate = byID[id],\n              candidate.freshlyCorrelated,\n              candidates.filter({ $0.freshlyCorrelated }).count == 1 else {\n            failLocally(\"No single current-session correlated Bluetooth target is awaiting confirmation. Restart from OFF1 rather than guessing.\", \"correlated_target_confirmation_unavailable\")\n            return\n        }\n        guard fieldBuildIsAuthoritative,\n              privateConfig,\n              sdkAccountLoggedIn,\n              sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized else {\n            pendingCorrelatedID = nil\n            targetCorrelationOperatorConfirmed = false\n            failLocally(\"Build or same-account exact-device authority changed before target confirmation. Re-verify authority and repeat the fresh correlation series.\", \"correlated_target_confirmation_authority_changed\")\n            return\n        }\n\n        selectedID = id\n        pendingCorrelatedID = nil\n        targetCorrelationOperatorConfirmed = true\n        phase = .selected\n        message = \"Correlated Bluetooth target confirmed for this attempt. The UUID remains current-session correlation evidence, not permanent scooter identity. Tuya SDK authentication can now be started.\"\n        log(\"candidate_selected\", [\n            \"id\": id.uuidString,\n            \"authority\": \"operator-confirmed-current-session-correlation\",\n            \"correlationMethod\": targetCorrelationMethod ?? \"unknown\"\n        ])\n    }\n\n    func invalidateSDKMembership() {\n""",
    "explicit target confirmation authority boundary",
)
source = replace_once(
    source,
    """        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n""",
    """        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            stopCorrelationProgressObservation()\n            correlationProgress = nil\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        if phase == .correlated {\n            pendingCorrelatedID = nil\n            targetCorrelationOperatorConfirmed = false\n        }\n""",
    "membership invalidation clears unconfirmed correlation",
)
source = replace_once(
    source,
    """        if [.baseline, .powerOn, .scanning, .selected].contains(phase) {\n""",
    """        if [.baseline, .powerOn, .scanning, .correlated, .selected].contains(phase) {\n""",
    "membership invalidation covers confirmation phase",
)

# Auth-start and post-await promotion must never strand or resurrect a generation.
source = replace_once(
    source,
    """                let token = try await self.sessionLedger.beginConnection()\n                try await self.sessionLedger.markAuthenticationStarted(for: token)\n                self.currentConnectionToken = token\n                await self.refreshLedgerSnapshot()\n""",
    """                let token = try await self.sessionLedger.beginConnection()\n                self.currentConnectionToken = token\n                do {\n                    try await self.sessionLedger.markAuthenticationStarted(for: token)\n                } catch {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: \"Authentication-start chronology failed closed: \\(error.localizedDescription)\",\n                        kind: \"session_authentication_start_rejected\"\n                    )\n                    return\n                }\n                await self.refreshLedgerSnapshot()\n""",
    "own minted token before auth-start mutation",
)
source = replace_once(
    source,
    """                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)\n                    await refreshLedgerSnapshot()\n                    phase = .observing\n                    message = \"Authenticated generation \\(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…\"\n""",
    """                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)\n                    await refreshLedgerSnapshot()\n                    guard currentConnectionToken == token,\n                          phase == .authenticating,\n                          localBLESettlementToken == token else {\n                        log(\"stale_authentication_promotion_resume_ignored\", [\"generation\": String(token.diagnosticGeneration)])\n                        return\n                    }\n                    guard sdkAccountLoggedIn,\n                          sdkDeviceMembershipVerified,\n                          accountIdentityLeaseIsAuthorized else {\n                        await retirePromotedSourceDrift(token: token)\n                        return\n                    }\n                    phase = .observing\n                    message = \"Authenticated generation \\(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…\"\n""",
    "post-auth actor-hop resume fence",
)
source = replace_once(
    source,
    """                } catch {\n                    await invalidateSourceAuthority(\n                        token: token,\n                        message: \"Authenticated-session chronology rejected the SDK success callback: \\(error.localizedDescription)\",\n                        kind: \"session_auth_callback_rejected\"\n                    )\n                }\n""",
    """                } catch {\n                    await invalidateInternalLifecycle(\n                        token: token,\n                        message: \"Authenticated-session chronology rejected the SDK success callback: \\(error.localizedDescription)\",\n                        kind: \"session_auth_callback_rejected\"\n                    )\n                }\n""",
    "auth-promotion rejection uses internal terminal",
)
source = replace_once(
    source,
    """            case .invalidClock:\n                await authenticationAcquisitionFailed(\n                    token: token,\n                    message: \"Local-BLE settlement failed closed because the monotonic clock regressed.\",\n                    kind: \"sdk_local_ble_settlement_clock_invalid\"\n                )\n""",
    """            case .invalidClock:\n                await invalidateInternalLifecycle(\n                    token: token,\n                    message: \"Local-BLE settlement failed closed because the monotonic clock regressed.\",\n                    kind: \"sdk_local_ble_settlement_clock_invalid\"\n                )\n""",
    "invalid local-BLE clock uses no-clock terminal",
)
source = replace_once(
    source,
    """        guard currentConnectionToken == token else { return }\n        try? await sessionLedger.markAuthenticationFailed(for: token)\n        currentConnectionToken = nil\n""",
    """        guard currentConnectionToken == token else { return }\n        do {\n            try await sessionLedger.markAuthenticationFailed(for: token)\n        } catch {\n            await invalidateInternalLifecycle(\n                token: token,\n                message: \"Authentication failure could not be terminally recorded: \\(error.localizedDescription)\",\n                kind: \"authentication_failure_terminal_rejected\"\n            )\n            return\n        }\n        currentConnectionToken = nil\n""",
    "authentication failure cannot swallow terminal failure",
)
source = replace_once(
    source,
    """                guard now >= previousPollUptime else {\n                    do {\n                        try await sessionLedger.markObservationContinuityInvalidated(for: token)\n                    } catch {}\n                    self.currentConnectionToken = nil\n                    await self.refreshLedgerSnapshot()\n                    self.failLocally(\"Authenticated observation continuity was interrupted by a monotonic-clock regression.\", \"observation_clock_regressed\")\n                    return\n                }\n""",
    """                guard now >= previousPollUptime else {\n                    await self.invalidateInternalLifecycle(\n                        token: token,\n                        message: \"Authenticated observation continuity was interrupted by a monotonic-clock regression.\",\n                        kind: \"observation_clock_regressed\"\n                    )\n                    return\n                }\n""",
    "watchdog clock regression uses no-clock terminal",
)
source = replace_once(
    source,
    """                guard gap <= Self.maximumObservationPollGapNanoseconds else {\n                    do {\n                        try await sessionLedger.markObservationContinuityInvalidated(for: token)\n                    } catch {}\n                    self.currentConnectionToken = nil\n                    await self.refreshLedgerSnapshot()\n                    self.failLocally(\"Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.\", \"observation_poll_gap_exceeded\")\n                    return\n                }\n""",
    """                guard gap <= Self.maximumObservationPollGapNanoseconds else {\n                    await self.invalidateObservationContinuity(\n                        token: token,\n                        message: \"Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.\",\n                        kind: \"observation_poll_gap_exceeded\"\n                    )\n                    return\n                }\n""",
    "watchdog gap uses checked continuity terminal",
)
source = replace_once(
    source,
    """                    do {\n                        try await sessionLedger.markApplicationObservationTimedOut(for: token)\n                    } catch {}\n                    self.currentConnectionToken = nil\n                    self.sdkLocalBLEOnline = false\n                    self.driver = nil\n                    await self.refreshLedgerSnapshot()\n                    self.phase = .failed\n                    self.message = \"Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.\"\n                    self.log(\"authenticated_application_timeout\", [\"generation\": String(token.diagnosticGeneration)])\n                    return\n""",
    """                    do {\n                        try await sessionLedger.markApplicationObservationTimedOut(for: token)\n                    } catch {\n                        await self.invalidateInternalLifecycle(\n                            token: token,\n                            message: \"Application-observation deadline could not be terminally recorded: \\(error.localizedDescription)\",\n                            kind: \"application_timeout_terminal_rejected\"\n                        )\n                        return\n                    }\n                    self.currentConnectionToken = nil\n                    self.localBLESettlementToken = nil\n                    self.sdkLocalBLEOnline = false\n                    self.driver = nil\n                    await self.refreshLedgerSnapshot()\n                    self.phase = .failed\n                    self.message = \"Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.\"\n                    self.log(\"authenticated_application_timeout\", [\"generation\": String(token.diagnosticGeneration)])\n                    return\n""",
    "application timeout checks terminal mutation",
)
source = replace_once(
    source,
    """    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {\n        guard currentConnectionToken == token else { return }\n        try? await sessionLedger.endConnection(for: token)\n        currentConnectionToken = nil\n""",
    """    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {\n        guard currentConnectionToken == token else { return }\n        do {\n            try await sessionLedger.endConnection(for: token)\n        } catch {\n            await invalidateInternalLifecycle(\n                token: token,\n                message: \"Observed transport loss could not be terminally recorded: \\(error.localizedDescription)\",\n                kind: \"transport_loss_terminal_rejected\"\n            )\n            return\n        }\n        currentConnectionToken = nil\n""",
    "transport loss checks terminal mutation",
)
source = replace_once(
    source,
    """    private func invalidateSourceAuthority(\n        token: TuyaReadOnlyConnectionToken,\n        message: String,\n        kind: String\n    ) async {\n        guard currentConnectionToken == token else { return }\n        try? await sessionLedger.markSourceAuthorityInvalidated(for: token)\n        currentConnectionToken = nil\n""",
    """    private func retirePromotedSourceDrift(token: TuyaReadOnlyConnectionToken) async {\n        await invalidateSourceAuthority(\n            token: token,\n            message: \"Tuya account/device source authority changed while authenticated promotion was yielding back to the app.\",\n            kind: \"sdk_source_authority_lost_during_auth_promotion\"\n        )\n    }\n\n    private func invalidateSourceAuthority(\n        token: TuyaReadOnlyConnectionToken,\n        message: String,\n        kind: String\n    ) async {\n        guard currentConnectionToken == token else { return }\n        do {\n            try await sessionLedger.markSourceAuthorityInvalidated(for: token)\n        } catch {\n            await invalidateInternalLifecycle(\n                token: token,\n                message: \"Source-authority terminal failed closed: \\(error.localizedDescription)\",\n                kind: \"source_authority_terminal_rejected\"\n            )\n            return\n        }\n        currentConnectionToken = nil\n""",
    "source invalidation checks terminal mutation",
)
source = replace_once(
    source,
    """    private func invalidateObservationContinuity(\n        token: TuyaReadOnlyConnectionToken,\n        message: String,\n        kind: String\n    ) async {\n        guard currentConnectionToken == token else { return }\n        try? await sessionLedger.markObservationContinuityInvalidated(for: token)\n        currentConnectionToken = nil\n""",
    """    private func invalidateObservationContinuity(\n        token: TuyaReadOnlyConnectionToken,\n        message: String,\n        kind: String\n    ) async {\n        guard currentConnectionToken == token else { return }\n        do {\n            try await sessionLedger.markObservationContinuityInvalidated(for: token)\n        } catch {\n            await invalidateInternalLifecycle(\n                token: token,\n                message: \"Observation-continuity terminal failed closed: \\(error.localizedDescription)\",\n                kind: \"observation_continuity_terminal_rejected\"\n            )\n            return\n        }\n        currentConnectionToken = nil\n""",
    "continuity invalidation checks terminal mutation",
)
source = replace_once(
    source,
    """    private func refreshLedgerSnapshot() async {\n        ledgerSnapshot = await sessionLedger.currentPreflightSnapshot()\n    }\n""",
    """    private func invalidateInternalLifecycle(\n        token: TuyaReadOnlyConnectionToken,\n        message: String,\n        kind: String\n    ) async {\n        guard currentConnectionToken == token else { return }\n        do {\n            try await sessionLedger.markInternalLifecycleFailure(for: token)\n        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {\n            // The package has already retired authority. Local ownership may now follow it.\n            log(\"internal_terminal_already_retired\", [\"generation\": String(token.diagnosticGeneration)])\n        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {\n            localBLESettlementToken = nil\n            sdkLocalBLEOnline = false\n            driver = nil\n            watchdog?.cancel()\n            watchdog = nil\n            await refreshLedgerSnapshot()\n            phase = .failed\n            self.message = message + \" Ledger generation ownership diverged; relaunch Capture before another attempt.\"\n            log(kind + \"_ledger_generation_diverged\", [\"generation\": String(token.diagnosticGeneration)])\n            return\n        } catch {\n            localBLESettlementToken = nil\n            sdkLocalBLEOnline = false\n            driver = nil\n            watchdog?.cancel()\n            watchdog = nil\n            await refreshLedgerSnapshot()\n            phase = .failed\n            self.message = message + \" Internal terminal could not prove callback retirement; relaunch Capture.\"\n            log(kind + \"_terminal_failed\", [\"generation\": String(token.diagnosticGeneration)])\n            return\n        }\n\n        currentConnectionToken = nil\n        localBLESettlementToken = nil\n        sdkLocalBLEOnline = false\n        driver = nil\n        watchdog?.cancel()\n        watchdog = nil\n        await refreshLedgerSnapshot()\n        phase = .failed\n        self.message = message\n        log(kind, [\"generation\": String(token.diagnosticGeneration)])\n    }\n\n    private func refreshLedgerSnapshot() async {\n        ledgerSnapshot = await sessionLedger.currentPreflightSnapshot()\n    }\n""",
    "internal no-clock app terminal",
)

# Reset/failure boundaries and app-owned scanner retirement.
source = replace_once(
    source,
    """    private func resetDiscoverySessionOnly() {\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        correlationProvenance = nil\n""",
    """    private func resetDiscoverySessionOnly() {\n        stopCorrelationProgressObservation()\n        correlationProgress = nil\n        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        pendingCorrelatedID = nil\n        correlationProvenance = nil\n""",
    "reset retires progress and pending candidate",
)
source = remove_exact_count(source, "        central.stopScan()\n", 4, "retire all app scan stops")
source = replace_once(source, "        baseline.removeAll()\n", "", "retire baseline candidate cache")
source = replace_once(
    source,
    """    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        watchdog?.cancel()\n""",
    """    private func failLocally(_ text: String, _ kind: String) {\n        if phase == .baseline || phase == .powerOn || phase == .scanning {\n            stopCorrelationProgressObservation()\n            correlationProgress = nil\n            correlationSession?.abandonCurrentWindow()\n            correlationSession = nil\n        }\n        if phase == .correlated {\n            pendingCorrelatedID = nil\n            targetCorrelationOperatorConfirmed = false\n        }\n        watchdog?.cancel()\n""",
    "local failure retires presentation and pending target",
)
legacy_start = source.find("    private static func hasTuyaCompanyID")
legacy_end_marker = "\n@MainActor\nprivate protocol OfficialTuyaDriver: AnyObject {"
legacy_end = source.find(legacy_end_marker)
if legacy_start < 0 or legacy_end < 0 or legacy_end <= legacy_start:
    raise SystemExit("legacy scanner section markers missing")
source = source[:legacy_start] + "}\n" + source[legacy_end:]

# Truthful field-build presentation and explicit confirmation UI.
source = replace_once(
    source,
    """            LabeledContent(\"Field build\", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? \"Authority checked\" : \"Not ready\")\n""",
    """            LabeledContent(\"Field build\", value: test.fieldBuildIsAuthoritative ? \"Authoritative · \\(test.fieldBuildIdentifier)\" : \"Not authoritative\")\n            if !test.fieldBuildIsAuthoritative {\n                Text(test.fieldBuildBlocker ?? \"Exact compiled field-build provenance is unavailable.\")\n                    .font(.footnote)\n                    .foregroundStyle(.orange)\n            }\n""",
    "field-build row uses build identity",
)
source = replace_once(
    source,
    """            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n""",
    """            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {\n""",
    "NO-GO banner consumes build authority",
)
source = replace_once(
    source,
    """                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n""",
    """                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n""",
    "OFF1 button consumes build authority",
)
source = replace_once(
    source,
    """            case .powerOn:\n                Text(\"Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)\")\n                    .foregroundStyle(.secondary)\n                Button(\"Start \\(test.correlationWindowLabel) window\") { test.startNextCorrelationWindow() }\n                    .buttonStyle(.borderedProminent)\n\n            default:\n""",
    """            case .powerOn:\n                Text(\"Next: \\(test.correlationWindowLabel) · \\(test.correlationWindowInstruction)\")\n                    .foregroundStyle(.secondary)\n                Button(\"Start \\(test.correlationWindowLabel) window\") { test.startNextCorrelationWindow() }\n                    .buttonStyle(.borderedProminent)\n\n            case .correlated:\n                Text(\"One full UUID repeated the required four-window pattern. Correlation is not permanent identity and is not selected until you confirm it.\")\n                    .font(.footnote)\n                    .foregroundStyle(.secondary)\n                if let candidate = test.pendingCorrelatedCandidate {\n                    Text(candidate.id.uuidString)\n                        .font(.caption.monospaced())\n                        .foregroundStyle(.secondary)\n                    Button(\"Confirm correlated Bluetooth target\") { test.confirmCorrelatedTarget() }\n                        .buttonStyle(.borderedProminent)\n                        .disabled(!test.fieldBuildIsAuthoritative || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)\n                }\n\n            default:\n""",
    "explicit target confirmation UI",
)
source = replace_once(
    source,
    """                    !candidate.likely\n                        || !test.privateConfig\n""",
    """                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.privateConfig\n""",
    "authentication UI consumes build authority",
)

# The older provenance source contract accidentally spanned into the confirmation function,
# making its `!= true` expectation unsatisfiable. Isolate only finishCorrelationSeries.
prov = PROVENANCE_TEST.read_text()
prov = replace_once(
    prov,
    """            from: \"private func finishCorrelationSeries\",\n            to: \"func invalidateSDKMembership\"\n""",
    """            from: \"private func finishCorrelationSeries\",\n            to: \"func confirmCorrelatedTarget\"\n""",
    "make provenance finish-section boundary satisfiable",
)
PROVENANCE_TEST.write_text(prov)

# Permanently pin the actor-hop resurrection fence discovered during adversarial review.
RESUME_TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture authentication-promotion resume fence")
struct TuyaAuthenticationPromotionResumeFenceSourceTests {
    @Test("auth promotion revalidates generation and source authority after the ledger actor hop")
    func authenticatedActorHopCannotRepaintATerminalGenerationAsObserving() throws {
        let app = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        guard let authenticated = app.range(of: "private func authenticated(token:"),
              let nextFunction = app.range(of: "private func authenticationFailed", range: authenticated.upperBound..<app.endIndex) else {
            Issue.record("Could not isolate the Tuya transport-success handler.")
            return
        }
        let handler = String(app[authenticated.lowerBound..<nextFunction.lowerBound])
        guard let promote = handler.range(of: "try await sessionLedger.markAuthenticated"),
              let observing = handler.range(of: "phase = .observing", range: promote.upperBound..<handler.endIndex) else {
            Issue.record("Could not isolate authenticated ledger promotion before observing UI state.")
            return
        }
        let resumeFence = String(handler[promote.upperBound..<observing.lowerBound])
        #expect(resumeFence.contains("currentConnectionToken == token"))
        #expect(resumeFence.contains("phase == .authenticating"))
        #expect(resumeFence.contains("localBLESettlementToken == token"))
        #expect(resumeFence.contains("accountIdentityLeaseIsAuthorized"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
''')

APP.write_text(source)
print("capture composed app red closure staged")
