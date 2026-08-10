from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, got {count}")
    s = s.replace(old, new, 1)


def remove_once(old: str, label: str) -> None:
    replace_once(old, "", label)


def function_bounds(marker: str) -> tuple[int, int]:
    start = s.find(marker)
    if start < 0:
        raise SystemExit(f"function missing: {marker}")
    brace = s.find("{", start)
    if brace < 0:
        raise SystemExit(f"opening brace missing: {marker}")
    depth = 0
    i = brace
    while i < len(s):
        ch = s[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return start, i + 1
        i += 1
    raise SystemExit(f"unbalanced function: {marker}")


def replace_function(marker: str, new: str) -> None:
    global s
    start, end = function_bounds(marker)
    s = s[:start] + new.rstrip() + s[end:]


# The package-owned four-window producer is the only discovery scanner.
remove_once("@preconcurrency import CoreBluetooth\n", "legacy CoreBluetooth import")
remove_once("\nlet CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n", "legacy advertisement alias")
remove_once("    static let fd50 = CBUUID(string: \"FD50\")\n", "legacy FD50 scanner constant")
remove_once("    private var central: CBCentralManager!\n", "legacy app central")
remove_once("    private var baseline = Set<UUID>()\n", "legacy baseline set")
remove_once("        central = CBCentralManager(delegate: self, queue: .main)\n", "legacy central initialization")
# These calls are all legacy app-scanner ownership; Tuya owns BLE only after correlation retires.
s = s.replace("        central.stopScan()\n", "")
s = s.replace("        baseline.removeAll()\n", "")

legacy_helpers_start = s.find("    private static func hasTuyaCompanyID")
legacy_extension_start = s.find("extension SecureLinkController: @preconcurrency CBCentralManagerDelegate")
protocol_start = s.find("@MainActor\nprivate protocol OfficialTuyaDriver", legacy_extension_start)
if legacy_helpers_start < 0 or legacy_extension_start < 0 or protocol_start < 0:
    raise SystemExit("legacy app-owned discovery block anchors missing")
s = s[:legacy_helpers_start] + "}\n\n" + s[protocol_start:]

# Make compiled field provenance visible instead of conflating it with Tuya account authority.
replace_once(
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var sdkAccountLoggedIn: Bool { OfficialTuyaFactory.accountLoggedIn }",
    "field build presentation property",
)
replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance verified" : "Not authoritative")',
    "field build row",
)
replace_once(
    "            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {",
    "field build NO-GO banner",
)
replace_once(
    "                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "OFF1 compiled build gate",
)
replace_once(
    "                    .disabled(!test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "                    .disabled(!test.fieldBuildIsAuthoritative || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)",
    "confirmation compiled build gate",
)
replace_once(
    "                    !candidate.likely\n                        || !test.privateConfig",
    "                    !candidate.likely\n                        || !test.fieldBuildIsAuthoritative\n                        || !test.privateConfig",
    "authentication compiled build gate",
)

replace_function(
    "    func confirmCorrelatedTarget()",
    '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              selectedID == nil,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated,
              candidates.count == 1,
              targetCorrelationMethod == "package-owned-fresh-manager-off1-on1-off2-on2",
              targetCorrelationWindowCount == 4,
              correlationProvenance?.repeatableCandidateIDs == [id.uuidString] else {
            pendingCorrelatedTargetID = nil
            failLocally("A complete current-session correlated Bluetooth target is not awaiting valid confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard buildIdentity.isAuthoritativeFieldBuild,
              sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Build or Tuya account/device authority changed before target confirmation. Re-verify authority and restart correlation from OFF1.", "source_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            let token = currentConnectionToken!
            pendingCorrelatedTargetID = nil
            targetCorrelationOperatorConfirmed = false
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "An authenticated generation unexpectedly still owned session authority at target confirmation. It was terminally retired; restart from OFF1.",
                    kind: "active_generation_blocks_target_confirmation"
                )
            }
            return
        }

        selectedID = id
        pendingCorrelatedTargetID = nil
        targetCorrelationOperatorConfirmed = true
        phase = .selected
        message = "Correlated Bluetooth target confirmed for this attempt. This remains current-session correlation evidence, not permanent scooter identity. Current same-account Tuya membership remains the independent authentication authority."
        log("candidate_selected", [
            "id": candidate.id.uuidString,
            "authority": "explicit-operator-confirmation-of-current-session-correlation",
            "historicalCaptureUUIDMatch": String(candidate.historicalCaptureID)
        ])
    }''',
)

# A source-identity change invalidates any confirmation earned under that lease.
replace_once(
    "        pendingCorrelatedTargetID = nil\n        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {",
    "        pendingCorrelatedTargetID = nil\n        targetCorrelationOperatorConfirmed = false\n        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {",
    "membership invalidates confirmation",
)
replace_once(
    '''    func authenticate() {
        guard let candidate = selected, candidate.likely else {
            failLocally("A fresh repeated OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")''',
    '''    func authenticate() {
        guard targetCorrelationOperatorConfirmed,
              let candidate = selected,
              candidate.likely else {
            failLocally("An explicitly confirmed fresh OFF1→ON1→OFF2→ON2 Bluetooth correlation is required before Tuya BLE ownership.", "candidate_not_authoritative")''',
    "authentication consumes confirmation fact",
)

replace_function(
    "    private func beginOfficialConnection(candidate: Candidate)",
    '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard targetCorrelationOperatorConfirmed,
              candidate.likely,
              buildIdentity.isAuthoritativeFieldBuild,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Build or Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            failLocally("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        driver = newDriver
        watchdog?.cancel()
        watchdog = nil
        sdkLocalBLEOnline = false
        localBLESettlementToken = nil
        phase = .authenticating
        message = "Tuya's SDK is establishing the supported secure BLE session. Nembra sends no DP query or command."

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let token = try await self.sessionLedger.beginConnection()
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    try? await self.sessionLedger.markInternalLifecycleFailure(for: token)
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authentication start failed closed because session chronology regressed. Restart from a fresh correlation."
                    self.log("authentication_start_clock_regressed", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication start could not establish trustworthy session chronology: \\(error.localizedDescription)",
                        kind: "authentication_start_lifecycle_rejected"
                    )
                    return
                }
                await self.refreshLedgerSnapshot()
                self.log("official_connect_requested", [
                    "generation": String(token.diagnosticGeneration),
                    "coreBluetoothID": candidate.id.uuidString,
                    "tuyaDeviceID": self.deviceID,
                    "tuyaUUID": self.tuyaUUID,
                    "productID": self.productID
                ])
                newDriver.connect(
                    deviceID: self.deviceID,
                    uuid: self.tuyaUUID,
                    productID: self.productID,
                    onApplicationUpdate: { [weak self] update in
                        Task { @MainActor in
                            await self?.receivedApplicationUpdate(update, token: token)
                        }
                    },
                    success: { [weak self] in
                        Task { @MainActor in await self?.authenticated(token: token) }
                    },
                    failure: { [weak self] in
                        Task { @MainActor in await self?.authenticationFailed(token: token) }
                    }
                )
            } catch {
                self.failLocally("Could not create a fresh authenticated-session generation: \\(error.localizedDescription)", "session_generation_failed")
            }
        }
    }''',
)

# Authentication promotion and settlement clock failures are internal lifecycle failures, not source drift.
old = '''                do {
                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
                    message = "Authenticated generation \\(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration),
                        "localBLEOnline": "true"
                    ])
                    startWatchdog(token: token)
                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \\(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return'''
new = '''                do {
                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
                    message = "Authenticated generation \\(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration),
                        "localBLEOnline": "true"
                    ])
                    startWatchdog(token: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication promotion failed closed because session chronology regressed.",
                        kind: "authentication_promotion_clock_regressed"
                    )
                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \\(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return'''
replace_once(old, new, "authentication promotion terminal")
replace_once(
    '''            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return''',
    '''            case .invalidClock:
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return''',
    "local BLE invalid clock terminal",
)

replace_function(
    "    private func authenticationFailed(token: TuyaReadOnlyConnectionToken)",
    '''    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_failure_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before the SDK failure callback could be classified.",
                kind: "sdk_source_authority_lost_before_failure_terminal"
            )
            return
        }
        await authenticationAcquisitionFailed(
            token: token,
            message: "Tuya SmartLife SDK did not establish the supported BLE session.",
            kind: "official_connect_failed"
        )
    }''',
)

replace_function(
    "    private func authenticationAcquisitionFailed(",
    '''    private func authenticationAcquisitionFailed(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }''',
)

# Application receipts preserve the distinction between a broken clock and an observation gap.
replace_once(
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])''',
    '''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application receipt chronology regressed; the current generation was terminally retired without inventing continuity evidence.",
                kind: "application_update_clock_regressed"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])''',
    "application update monotonic terminal",
)

# Watchdog: no path may ask a regressed clock to timestamp its own cleanup.
replace_once(
    '''                guard now >= previousPollUptime else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted by a monotonic-clock regression.", "observation_clock_regressed")
                    return
                }''',
    '''                guard now >= previousPollUptime else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated observation chronology regressed; the generation was retired without inventing a later receipt.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }''',
    "watchdog raw clock regression",
)
replace_once(
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])''',
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness chronology regressed; the generation was terminally retired.",
                        kind: "watchdog_liveness_clock_regressed"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])''',
    "watchdog observation monotonic terminal",
)
replace_once(
    '''                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted''',
    '''                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted''',
    "seal anchor",
)
replace_once(
    '''                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
                    return''',
    '''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness could not be sealed because session chronology regressed.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
                    return''',
    "seal monotonic terminal",
)
replace_once(
    '''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }''',
    '''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The no-application deadline could not be sealed because session chronology regressed.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The no-application deadline could not be terminally sealed: \\(error.localizedDescription)",
                            kind: "application_timeout_terminal_rejected"
                        )
                        return
                    }
                    self.currentConnectionToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }''',
    "application timeout monotonic terminal",
)

replace_function(
    "    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken)",
    '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture."
        log("sdk_local_ble_dropped", ["generation": String(token.diagnosticGeneration)])
    }''',
)
replace_function(
    "    private func invalidateSourceAuthority(",
    '''    private func invalidateSourceAuthority(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }''',
)
replace_function(
    "    private func invalidateObservationContinuity(",
    '''    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch {
            try? await sessionLedger.markInternalLifecycleFailure(for: token)
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }''',
)

# Dedicated clock-independent cleanup boundary consumed by correlation and authenticated lifecycle paths.
refresh_marker = "    private func refreshLedgerSnapshot() async {"
if s.count(refresh_marker) != 1:
    raise SystemExit("refresh helper anchor missing or ambiguous")
internal_helper = '''    private func invalidateInternalLifecycle(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markInternalLifecycleFailure(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

'''
s = s.replace(refresh_marker, internal_helper + refresh_marker, 1)

# Final hard fences: legacy app scanner APIs must be absent from the product source.
for forbidden in [
    "private var central: CBCentralManager",
    "CBCentralManager(delegate: self",
    "CBCentralManagerDelegate",
    "central.scanForPeripherals",
    "central.stopScan",
    "private func updateCandidate",
    "didDiscover peripheral",
    "CBAdvertisementDataServiceUUIDsKey",
    "CBAdvertisementDataManufacturerDataKey",
    "CBAdvertisementDataIsConnectableKey",
]:
    if forbidden in s:
        raise SystemExit(f"legacy scanner residue: {forbidden}")

path.write_text(s)
