from pathlib import Path

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
SOURCE = PATH.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global SOURCE
    count = SOURCE.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact anchor, found {count}")
    SOURCE = SOURCE.replace(old, new, 1)


def replace_section(start: str, end: str, replacement: str, label: str) -> None:
    global SOURCE
    start_index = SOURCE.find(start)
    if start_index < 0:
        raise SystemExit(f"{label}: start marker missing: {start!r}")
    if SOURCE.find(start, start_index + 1) >= 0:
        raise SystemExit(f"{label}: start marker is not unique: {start!r}")
    end_index = SOURCE.find(end, start_index + len(start))
    if end_index < 0:
        raise SystemExit(f"{label}: end marker missing: {end!r}")
    SOURCE = SOURCE[:start_index] + replacement + SOURCE[end_index:]


replace_once(
    '''    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''',
    '''    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }

    var accountIdentityLeaseIsAuthorized: Bool {
        TuyaSDKAccountIdentityLeaseGate.verdict(for: accountIdentityLeaseSnapshot) == .authorized
    }
''',
    "field-build authority projection",
)

replace_once(
    '''        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }
''',
    '''        guard currentConnectionToken == nil else {
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "A prior authenticated generation was still active when a new correlation attempt was requested. The old generation was retired without manufacturing transport evidence.",
                        kind: "active_generation_blocks_discovery_reset"
                    )
                }
            }
            return
        }
''',
    "correlation reset active-generation cleanup",
)

replace_section(
    "    func confirmCorrelatedTarget() {",
    "    func invalidateSDKMembership() {",
    '''    func confirmCorrelatedTarget() {
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
                        message: "An authenticated generation unexpectedly still owned session authority during target confirmation. It was retired before any new target could be selected.",
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

''',
    "target confirmation lifecycle",
)

replace_section(
    "    private func beginOfficialConnection(candidate: Candidate) {",
    "    private func authenticated(token: TuyaReadOnlyConnectionToken)",
    '''    private func beginOfficialConnection(candidate: Candidate) {
        guard phase == .selected || phase == .failed else { return }
        guard candidate.likely,
              sdkDeviceMembershipVerified,
              sdkAccountLoggedIn,
              accountIdentityLeaseIsAuthorized else {
            failLocally("Tuya account/device authority changed before connection start.", "sdk_authority_changed")
            return
        }
        guard currentConnectionToken == nil else {
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "A previous authenticated generation still owned session authority when a new Tuya connection was requested.",
                        kind: "active_generation_blocks_authentication_start"
                    )
                }
            }
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

            let token: TuyaReadOnlyConnectionToken
            do {
                token = try await self.sessionLedger.beginConnection()
            } catch {
                self.failLocally("Could not create a fresh authenticated-session generation: \(error.localizedDescription)", "session_generation_failed")
                return
            }

            // App ownership begins as soon as the package mints the generation. A failure in the
            // next sampled mutation therefore cannot strand a package token the app never knew.
            self.currentConnectionToken = token
            do {
                try await self.sessionLedger.markAuthenticationStarted(for: token)
            } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                do {
                    try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                } catch {
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authentication-start chronology regressed and the no-clock terminal itself could not retire the generation. Relaunch Capture before another attempt."
                    self.log("authentication_start_internal_terminal_failed", [
                        "generation": String(token.diagnosticGeneration),
                        "error": error.localizedDescription
                    ])
                    return
                }
                if self.currentConnectionToken == token {
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                }
                await self.refreshLedgerSnapshot()
                self.phase = .failed
                self.message = "Authentication-start chronology regressed. The generation was retired without inventing a later timestamp."
                self.log("authentication_start_clock_regressed", ["generation": String(token.diagnosticGeneration)])
                return
            } catch {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authentication-start lifecycle was rejected before the Tuya driver could own the session.",
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
        }
    }

''',
    "authentication start lifecycle",
)

replace_section(
    "    private func authenticated(token: TuyaReadOnlyConnectionToken)",
    "    private func authenticationFailed(token:",
    '''    private func authenticated(token: TuyaReadOnlyConnectionToken) async {
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
                        message: "Authenticated-session chronology regressed while promoting Tuya transport success. The generation was retired without manufacturing source or continuity evidence.",
                        kind: "session_auth_clock_regressed"
                    )
                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated-session lifecycle rejected the SDK success callback: \(error.localizedDescription)",
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
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed. No authentication or source-authority fact was manufactured.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
            }
        }
    }

''',
    "authenticated promotion lifecycle",
)

replace_section(
    "    private func authenticationFailed(token:",
    "    private func receivedApplicationUpdate(",
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
                message: "Tuya account/device source authority had already changed when the SDK failure callback arrived.",
                kind: "sdk_source_authority_lost_before_failure_callback"
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
            } catch {
                await refreshLedgerSnapshot()
                log("authentication_failure_internal_terminal_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_authentication_failure_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_authentication_failure_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Authentication-failure lifecycle could not be recorded cleanly: \(error.localizedDescription)",
                kind: "authentication_failure_terminal_rejected"
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

''',
    "authentication failure lifecycle",
)

replace_section(
    "    private func receivedApplicationUpdate(",
    "    private func startWatchdog(token:",
    '''    private func receivedApplicationUpdate(
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application-receipt chronology regressed. The generation was retired without relabeling the failure as an observation gap.",
                kind: "application_update_clock_regressed"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }
    }

''',
    "application receipt chronology",
)

replace_section(
    "    private func startWatchdog(token:",
    "    private func recordObservedTransportLoss(token:",
    '''    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
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
                        message: "Authenticated observation chronology regressed. The generation was retired through the no-clock lifecycle terminal.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }

                let gap = now - previousPollUptime
                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the scheduling gap is not evidence that BLE disconnected.",
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
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness chronology regressed while observing the current connection.",
                        kind: "session_liveness_clock_regressed"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
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
                        try await self.sessionLedger.sealAcceptedObservation(for: token)
                        self.currentConnectionToken = nil
                        await self.refreshLedgerSnapshot()
                        self.phase = .accepted
                        self.message = "Secure scooter link established. Canonical readiness was sealed before UI acceptance; delayed callbacks cannot mutate the accepted prefix."
                        self.log("acceptance_sealed", [
                            "generation": String(token.diagnosticGeneration),
                            "applicationUpdates": String(self.applicationUpdateCount),
                            "buildIdentifier": self.buildIdentity.buildIdentifier,
                            "sourceCommitSHA": self.buildIdentity.sourceCommitSHA
                        ])
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance could not be sealed because monotonic chronology regressed.",
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
                        try await self.sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The no-application observation deadline encountered a monotonic-clock regression.",
                            kind: "authenticated_application_timeout_clock_regressed"
                        )
                        return
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                        self.log("stale_application_timeout_ignored", ["generation": String(token.diagnosticGeneration)])
                        return
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                        self.log("retired_application_timeout_ignored", ["generation": String(token.diagnosticGeneration)])
                        return
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The no-application observation terminal was rejected: \(error.localizedDescription)",
                            kind: "authenticated_application_timeout_terminal_rejected"
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

''',
    "watchdog chronology",
)

replace_section(
    "    private func recordObservedTransportLoss(token:",
    "    private func refreshLedgerSnapshot()",
    '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                await refreshLedgerSnapshot()
                log("transport_loss_internal_terminal_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
            currentConnectionToken = nil
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            await refreshLedgerSnapshot()
            phase = .failed
            message = "Tuya local BLE was observed offline, but ledger chronology regressed while retiring the session. Treat this as an internal lifecycle failure."
            log("sdk_local_ble_drop_clock_regressed", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_transport_loss_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_transport_loss_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Observed local-BLE loss could not be committed to the session ledger: \(error.localizedDescription)",
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
            } catch {
                await refreshLedgerSnapshot()
                log("source_authority_internal_terminal_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
            currentConnectionToken = nil
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = "Source authority changed, but the ledger clock regressed while recording that terminal. The generation was retired as an internal lifecycle failure."
            log("source_authority_clock_regressed", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_source_authority_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_source_authority_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Source-authority terminal failed closed: \(error.localizedDescription)",
                kind: "source_authority_terminal_rejected"
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
            } catch {
                await refreshLedgerSnapshot()
                log("continuity_internal_terminal_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
            currentConnectionToken = nil
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = "Observation continuity was invalid, but ledger chronology regressed while recording that terminal. The generation was retired as an internal lifecycle failure."
            log("observation_continuity_clock_regressed", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_continuity_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_continuity_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Observation-continuity terminal failed closed: \(error.localizedDescription)",
                kind: "observation_continuity_terminal_rejected"
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

    private func invalidateInternalLifecycle(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markInternalLifecycleFailure(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            await refreshLedgerSnapshot()
            log("stale_internal_lifecycle_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            await refreshLedgerSnapshot()
            log("retired_internal_lifecycle_terminal_ignored", ["generation": String(token.diagnosticGeneration)])
            return
        } catch {
            await refreshLedgerSnapshot()
            phase = .failed
            self.message = "Internal lifecycle retirement failed closed. Relaunch Capture before another attempt."
            log("internal_lifecycle_terminal_failed", [
                "generation": String(token.diagnosticGeneration),
                "error": error.localizedDescription
            ])
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

''',
    "terminal lifecycle cleanup",
)

replace_once(
    '            LabeledContent("Field build", value: test.accountIdentityLeaseIsAuthorized && test.sdkDeviceMembershipVerified ? "Authority checked" : "Not ready")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Exact provenance" : "Not authoritative")',
    "field-build row",
)

replace_once(
    '''            if !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: the private exact field build, current SDK account identity, and exact scooter membership must all be proven before even the OFF baseline scan can start.")
''',
    '''            if !test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized {
                Text("NO PHYSICAL BLE TEST YET: exact compiled field-build provenance, private SDK configuration, current SDK account identity, and exact scooter membership must all be proven before OFF1 correlation can start.")
''',
    "field-build NO-GO presentation",
)

replace_once(
    '''                    .disabled(!test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
    '''                    .disabled(!test.fieldBuildIsAuthoritative || !test.privateConfig || !test.sdkAccountLoggedIn || !test.sdkDeviceMembershipVerified || !test.accountIdentityLeaseIsAuthorized || test.membershipBusy)
''',
    "OFF1 build-authority affordance",
)

required = [
    "var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }",
    "private func invalidateInternalLifecycle",
    "sessionLedger.markInternalLifecycleFailure(for: token)",
    "sdk_source_authority_lost_before_failure_callback",
    "targetCorrelationOperatorConfirmed = true",
]
for needle in required:
    if needle not in SOURCE:
        raise SystemExit(f"post-patch invariant missing: {needle}")

for forbidden in [
    "try? await sessionLedger.markAuthenticationFailed(for: token)",
    "try? await sessionLedger.markSourceAuthorityInvalidated(for: token)",
    "try? await sessionLedger.markObservationContinuityInvalidated(for: token)",
    "try? await sessionLedger.endConnection(for: token)",
]:
    if forbidden in SOURCE:
        raise SystemExit(f"post-patch swallowed terminal remains: {forbidden}")

PATH.write_text(SOURCE)
