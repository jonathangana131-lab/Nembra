from pathlib import Path
import re

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")


def sub_once(text: str, pattern: str, replacement: str, label: str) -> str:
    rx = re.compile(pattern, re.MULTILINE | re.DOTALL)
    found = list(rx.finditer(text))
    if len(found) != 1:
        raise SystemExit(f"{label}: expected one match, found {len(found)}")
    return rx.sub(lambda _: replacement, text, count=1)


app = APP.read_text()

confirmation = '''    func confirmCorrelatedTarget() {
        guard phase == .correlated,
              let id = pendingCorrelatedTargetID,
              let candidate = byID[id],
              candidate.freshlyCorrelated else {
            pendingCorrelatedTargetID = nil
            failLocally("A current-session correlated Bluetooth target is not awaiting confirmation. Restart from OFF1.", "correlated_target_confirmation_unavailable")
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            pendingCorrelatedTargetID = nil
            failLocally("Tuya account/device authority changed before target confirmation. Re-verify membership and restart correlation.", "sdk_authority_changed_before_target_confirmation")
            return
        }
        guard currentConnectionToken == nil else {
            pendingCorrelatedTargetID = nil
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "An authenticated generation unexpectedly existed during target confirmation. That generation was retired before any new target could be promoted.",
                        kind: "active_generation_blocks_target_confirmation"
                    )
                }
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
    }

    func invalidateSDKMembership() {'''
app = sub_once(
    app,
    r"    func confirmCorrelatedTarget\(\) \{.*?^    func invalidateSDKMembership\(\) \{",
    confirmation,
    "confirmation lifecycle ownership",
)

begin = '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard let newDriver = OfficialTuyaFactory.make() else {
            failLocally("Official Tuya provider is unavailable.", "sdk_provider_unavailable")
            return
        }

        central.stopScan()
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
                // Own the exact minted generation before any later ledger mutation can fail.
                // Otherwise a regressed clock at authentication-start could strand package
                // callback authority behind a nil app token.
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    do {
                        try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                        await self.retireAppOwnershipAfterLedgerTerminal(
                            token: token,
                            message: "Authentication-start chronology failed closed because the monotonic clock regressed.",
                            kind: "session_auth_start_clock_regressed"
                        )
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Authentication-start chronology failed closed because the monotonic clock regressed.",
                            kind: "session_auth_start_clock_regressed"
                        )
                    }
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication-start chronology was rejected: \(error.localizedDescription)",
                        kind: "session_auth_start_chronology_rejected"
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
                // beginConnection itself failed before a token was returned to this controller,
                // so there is no owned generation to retire here.
                self.failLocally("Could not mint a fresh authenticated-session generation: \(error.localizedDescription)", "session_generation_failed")
            }
        }
    }

    private func authenticated(token: TuyaReadOnlyConnectionToken) async {'''
app = sub_once(
    app,
    r"    private func beginOfficialConnection\(candidate: Candidate\) \{.*?^    private func authenticated\(token: TuyaReadOnlyConnectionToken\) async \{",
    begin,
    "authentication-start ownership",
)

authenticated = '''    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else {
            log("stale_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        if phase == .observing {
            log("duplicate_connect_success_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard phase == .authenticating else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya transport success arrived outside the active authentication phase. The generation was retired instead of being left hidden.",
                kind: "sdk_transport_success_outside_authentication"
            )
            return
        }
        guard localBLESettlementToken != token else {
            log("duplicate_connect_success_settlement_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        }
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized else {
            await invalidateSourceAuthority(
                token: token,
                message: "Tuya account/device source authority changed before transport success could enter local-BLE settlement.",
                kind: "sdk_source_authority_lost_before_local_ble_settlement"
            )
            return
        }
        guard let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "Official Tuya driver authority disappeared before local-BLE settlement.",
                kind: "sdk_driver_authority_lost_before_local_ble_settlement"
            )
            return
        }

        localBLESettlementToken = token
        defer {
            if localBLESettlementToken == token {
                localBLESettlementToken = nil
            }
        }

        let acquisitionStarted = DispatchTime.now().uptimeNanoseconds
        while currentConnectionToken == token, phase == .authenticating {
            guard sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "Tuya account/device source authority changed while local BLE status was settling.",
                    kind: "sdk_source_authority_lost_during_local_ble_settlement"
                )
                return
            }

            let observedAt = DispatchTime.now().uptimeNanoseconds
            let isLocallyOnline = driver.isLocallyConnected(uuid: tuyaUUID)
            switch TuyaLocalBLEAcquisitionWindow.verdict(
                startedAtUptimeNanoseconds: acquisitionStarted,
                observedAtUptimeNanoseconds: observedAt,
                isLocallyOnline: isLocallyOnline,
                maximumWaitNanoseconds: TuyaLocalBLEAcquisitionWindow.maximumWaitNanoseconds
            ) {
            case .observedOnline:
                sdkLocalBLEOnline = true
                do {
                    try await sessionLedger.markAuthenticated(for: token, method: .smartLifeAppSDK)
                    await refreshLedgerSnapshot()
                    phase = .observing
                    message = "Authenticated generation \(token.diagnosticGeneration) is live. Waiting for a genuine application update and the canonical 45-second horizon…"
                    log("sdk_local_ble_authenticated", [
                        "generation": String(token.diagnosticGeneration),
                        "localBLEOnline": "true"
                    ])
                    startWatchdog(token: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session promotion failed closed because the monotonic clock regressed.",
                        kind: "session_auth_callback_clock_regressed"
                    )
                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
                return

            case .keepWaiting:
                try? await Task.sleep(for: .milliseconds(200))

            case .timedOut:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Tuya reported transport success, but current local-BLE status did not become authoritative within the bounded settlement window.",
                    kind: "sdk_local_ble_settlement_timed_out"
                )
                return

            case .invalidClock:
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
            }
        }
    }

    private func authenticationFailed(token: TuyaReadOnlyConnectionToken) async {'''
app = sub_once(
    app,
    r"    private func authenticated\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func authenticationFailed\(token: TuyaReadOnlyConnectionToken\) async \{",
    authenticated,
    "transport success terminal truth",
)

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

    private func authenticationAcquisitionFailed(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
                await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_clock_regressed")
            } catch {
                await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_clock_regressed")
            }
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_after_ledger_terminal")
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "\(message) Authentication-failure terminal was rejected: \(error.localizedDescription)",
                kind: "\(kind)_terminal_rejected"
            )
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

    private func receivedApplicationUpdate('''
app = sub_once(
    app,
    r"    private func authenticationFailed\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func receivedApplicationUpdate\(",
    auth_failure,
    "SDK failure source race and fallback",
)

application = '''    private func receivedApplicationUpdate(
        _ update: [String: String],
        token: TuyaReadOnlyConnectionToken
    ) async {
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
        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
            message = "Receiving same-generation scooter application data · \(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(
                token: token,
                message: "The authenticated ledger generation was already terminal before this delayed application callback.",
                kind: "retired_application_update_ignored"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await retireAppOwnershipAfterLedgerTerminal(
                token: token,
                message: "Application chronology detected an invalid observation gap and retired the exact ledger generation.",
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
        }
    }

    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {'''
app = sub_once(
    app,
    r"    private func receivedApplicationUpdate\(.*?^    private func startWatchdog\(token: TuyaReadOnlyConnectionToken\) \{",
    application,
    "application chronology terminal classification",
)

watchdog = '''    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
        watchdog?.cancel()
        watchdog = Task { @MainActor [weak self] in
            var previousPollUptime = DispatchTime.now().uptimeNanoseconds

            while !Task.isCancelled {
                guard let self,
                      self.currentConnectionToken == token,
                      self.secureSessionEstablished,
                      let driver = self.driver else { return }

                let now = DispatchTime.now().uptimeNanoseconds
                guard now >= previousPollUptime else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated observation chronology was invalidated by a monotonic-clock regression.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }

                let gap = now - previousPollUptime
                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }
                previousPollUptime = now

                guard self.sdkAccountLoggedIn,
                      self.sdkDeviceMembershipVerified,
                      self.accountIdentityLeaseIsAuthorized else {
                    await self.invalidateSourceAuthority(
                        token: token,
                        message: "SDK account/device source authority changed during authenticated observation.",
                        kind: "sdk_source_authority_lost_during_observation"
                    )
                    return
                }

                self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)
                guard self.sdkLocalBLEOnline else {
                    await self.recordObservedTransportLoss(token: token)
                    return
                }

                do {
                    try await self.sessionLedger.observeCurrentConnection(for: token)
                    await self.refreshLedgerSnapshot()
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    await self.retireAppOwnershipAfterLedgerTerminal(
                        token: token,
                        message: "Authenticated-session liveness observed an already-retired ledger generation.",
                        kind: "sealed_watchdog_generation_retired"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.retireAppOwnershipAfterLedgerTerminal(
                        token: token,
                        message: "Authenticated-session liveness detected an invalid observation gap and retired the exact ledger generation.",
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
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }

                switch TuyaAuthenticatedReadOnlyPreflight.verdict(for: self.ledgerSnapshot) {
                case .readyForStationaryMapping:
                    guard self.buildIdentity.isAuthoritativeFieldBuild else {
                        await self.invalidateSourceAuthority(
                            token: token,
                            message: self.buildIdentity.blocker ?? "Exact field-build provenance became unavailable before acceptance.",
                            kind: "field_build_identity_rejected_at_seal"
                        )
                        return
                    }
                    guard self.accountIdentityLeaseIsAuthorized else {
                        await self.invalidateSourceAuthority(
                            token: token,
                            message: "Tuya account/device source authority changed before canonical acceptance could be sealed.",
                            kind: "sdk_source_authority_rejected_at_seal"
                        )
                        return
                    }
                    do {
                        try await sessionLedger.sealAcceptedObservation(for: token)
                        self.currentConnectionToken = nil
                        self.localBLESettlementToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
                        self.message = "Secure scooter link established. Canonical readiness was sealed before UI acceptance; delayed callbacks cannot mutate the accepted prefix."
                        self.log("acceptance_sealed", [
                            "generation": String(token.diagnosticGeneration),
                            "applicationUpdates": String(self.applicationUpdateCount),
                            "buildIdentifier": self.buildIdentity.buildIdentifier,
                            "sourceCommitSHA": self.buildIdentity.sourceCommitSHA
                        ])
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                        await self.retireAppOwnershipAfterLedgerTerminal(
                            token: token,
                            message: "Canonical readiness could not be sealed because observation continuity was invalidated.",
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
                    }
                    return

                case .blocked:
                    break
                }

                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Application-observation deadline could not be sealed because the monotonic clock regressed.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                        await self.retireAppOwnershipAfterLedgerTerminal(
                            token: token,
                            message: "Application-observation deadline found an already-retired ledger generation.",
                            kind: "application_timeout_after_ledger_terminal"
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
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture."
                    self.log("authenticated_application_timeout", ["generation": String(token.diagnosticGeneration)])
                    return
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {'''
app = sub_once(
    app,
    r"    private func startWatchdog\(token: TuyaReadOnlyConnectionToken\) \{.*?^    private func recordObservedTransportLoss\(token: TuyaReadOnlyConnectionToken\) async \{",
    watchdog,
    "watchdog terminal authority",
)

terminals = '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
                await retireAppOwnershipAfterLedgerTerminal(
                    token: token,
                    message: "Observed local-BLE loss could not seal chronology because the monotonic clock regressed.",
                    kind: "sdk_local_ble_drop_clock_regressed"
                )
            } catch {
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Observed local-BLE loss could not seal chronology because the monotonic clock regressed.",
                    kind: "sdk_local_ble_drop_clock_regressed"
                )
            }
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
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
                await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_clock_regressed")
            } catch {
                await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_clock_regressed")
            }
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_after_ledger_terminal")
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "\(message) Source-authority terminal was rejected: \(error.localizedDescription)",
                kind: "\(kind)_terminal_rejected"
            )
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
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
                await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_clock_regressed")
            } catch {
                await invalidateInternalLifecycle(token: token, message: message, kind: "\(kind)_clock_regressed")
            }
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await retireAppOwnershipAfterLedgerTerminal(token: token, message: message, kind: "\(kind)_after_ledger_terminal")
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "\(message) Observation-continuity terminal was rejected: \(error.localizedDescription)",
                kind: "\(kind)_terminal_rejected"
            )
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

    private func invalidateInternalLifecycle(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            currentConnectionToken = nil
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = message
            log("\(kind)_already_retired", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            // Keep the exact app token visible if package retirement is rejected. A visible
            // blocked generation is safer than clearing app ownership while package authority
            // could still exist. The user must relaunch before another attempt.
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

    private func refreshLedgerSnapshot() async {'''
app = sub_once(
    app,
    r"    private func recordObservedTransportLoss\(token: TuyaReadOnlyConnectionToken\) async \{.*?^    private func refreshLedgerSnapshot\(\) async \{",
    terminals,
    "terminal helper ownership",
)

# Mechanical truth assertions. These are intentionally source-local and fail before commit.
for forbidden in (
    "try? await sessionLedger.markAuthenticationFailed(for: token)",
    "try? await sessionLedger.markSourceAuthorityInvalidated(for: token)",
    "try? await sessionLedger.markObservationContinuityInvalidated(for: token)",
    "try? await sessionLedger.endConnection(for: token)",
):
    if forbidden in app:
        raise SystemExit(f"fail-open terminal remains: {forbidden}")

for required in (
    "private func invalidateInternalLifecycle(",
    "sessionLedger.markInternalLifecycleFailure(for: token)",
    "session_auth_start_clock_regressed",
    "session_auth_callback_clock_regressed",
    "sdk_local_ble_settlement_clock_invalid",
    "sdk_source_authority_lost_before_auth_failure",
    "application_update_clock_regressed",
    "observation_clock_regressed",
    "session_liveness_clock_regressed",
    "accepted_prefix_seal_clock_regressed",
    "application_timeout_clock_regressed",
    "active_generation_blocks_target_confirmation",
):
    if required not in app:
        raise SystemExit(f"required authority marker missing: {required}")

APP.write_text(app)
print("V14 Capture app internal-lifecycle consumer applied")
