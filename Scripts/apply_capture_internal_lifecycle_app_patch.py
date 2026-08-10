from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    s = s.replace(old, new, 1)


replace_once(
'''            do {
                let token = try await self.sessionLedger.beginConnection()
                try await self.sessionLedger.markAuthenticationStarted(for: token)
                self.currentConnectionToken = token
                await self.refreshLedgerSnapshot()
''',
'''            do {
                let token = try await self.sessionLedger.beginConnection()
                // Own the package generation before any later mutation can fail. Otherwise an
                // auth-start clock regression could strand callback authority in the ledger.
                self.currentConnectionToken = token
                do {
                    try await self.sessionLedger.markAuthenticationStarted(for: token)
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    do {
                        try await self.sessionLedger.markInternalLifecycleFailure(for: token)
                    } catch {
                        self.phase = .failed
                        self.message = "Authentication chronology failed and the exact generation could not be retired. Relaunch Capture before another attempt."
                        self.log("auth_start_terminal_retirement_failed", [
                            "generation": String(token.diagnosticGeneration),
                            "error": error.localizedDescription
                        ])
                        return
                    }
                    self.currentConnectionToken = nil
                    self.localBLESettlementToken = nil
                    self.sdkLocalBLEOnline = false
                    self.driver = nil
                    await self.refreshLedgerSnapshot()
                    self.phase = .failed
                    self.message = "Authentication chronology failed closed before the Tuya connection request. The exact generation was retired without sampling the broken clock again."
                    self.log("auth_start_clock_regressed", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication-start lifecycle mutation failed closed before the Tuya connection request: \\(error.localizedDescription)",
                        kind: "auth_start_lifecycle_rejected"
                    )
                    return
                }
                await self.refreshLedgerSnapshot()
''',
"own token before auth-start mutation",
)

replace_once(
'''                } catch {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "Authenticated-session chronology rejected the SDK success callback: \\(error.localizedDescription)",
                        kind: "session_auth_callback_rejected"
                    )
                }
''',
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication promotion failed closed because monotonic chronology regressed.",
                        kind: "session_auth_promotion_clock_regressed"
                    )
                } catch {
                    await invalidateInternalLifecycle(
                        token: token,
                        message: "Authentication promotion violated the current internal session lifecycle: \\(error.localizedDescription)",
                        kind: "session_auth_promotion_rejected"
                    )
                }
''',
"auth promotion is internal lifecycle, not source drift",
)

replace_once(
'''            case .invalidClock:
                await authenticationAcquisitionFailed(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
''',
'''            case .invalidClock:
                await invalidateInternalLifecycle(
                    token: token,
                    message: "Local-BLE settlement failed closed because the monotonic clock regressed. The exact generation was retired without resampling that clock.",
                    kind: "sdk_local_ble_settlement_clock_invalid"
                )
                return
''',
"invalid local BLE settlement clock",
)

replace_once(
'''        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markAuthenticationFailed(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
''',
'''        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markAuthenticationFailed(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Authentication terminal chronology failed and the exact generation could not be retired. Relaunch Capture before another attempt."
                log("authentication_terminal_retirement_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Authentication failure could not terminally retire the exact generation. Relaunch Capture before another attempt."
                log("authentication_terminal_retirement_failed", [
                    "generation": String(token.diagnosticGeneration),
                    "error": error.localizedDescription
                ])
                return
            }
        }
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
''',
"authentication terminal fallback",
)

replace_once(
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateObservationContinuity(
                token: token,
                message: "Application chronology failed closed: \\(error.localizedDescription)",
                kind: "application_update_rejected"
            )
        }
''',
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application receipt chronology failed closed because the monotonic clock regressed.",
                kind: "application_receipt_clock_regressed"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await invalidateObservationContinuity(
                token: token,
                message: "Application receipt arrived after authenticated observation continuity was already invalid.",
                kind: "application_observation_continuity_invalidated"
            )
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
            log("retired_application_update_ignored", ["generation": String(token.diagnosticGeneration)])
        } catch {
            await invalidateInternalLifecycle(
                token: token,
                message: "Application receipt violated the current internal session lifecycle: \\(error.localizedDescription)",
                kind: "application_update_lifecycle_rejected"
            )
        }
''',
"application mutation clock classification",
)

replace_once(
'''                guard now >= previousPollUptime else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted by a monotonic-clock regression.", "observation_clock_regressed")
                    return
                }
''',
'''                guard now >= previousPollUptime else {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated observation chronology regressed. The exact generation was retired without sampling the broken clock again.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }
''',
"watchdog local clock regression",
)

replace_once(
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \\(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }
''',
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness chronology regressed. The exact generation was retired without another clock sample.",
                        kind: "session_liveness_clock_regressed"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness exceeded the accepted continuous-observation horizon.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {
                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateInternalLifecycle(
                        token: token,
                        message: "Authenticated liveness violated the current internal session lifecycle: \\(error.localizedDescription)",
                        kind: "session_liveness_lifecycle_rejected"
                    )
                    return
                }
''',
"watchdog ledger mutation classification",
)

replace_once(
'''                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
''',
'''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance sealing encountered a monotonic-clock regression.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Canonical readiness could not be sealed: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_failed"
                        )
                    }
''',
"accepted seal clock fallback",
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
                }
''',
'''                if (self.canonicalObservedAgeSeconds ?? 0) > 60,
                   self.applicationUpdateCount == 0 {
                    do {
                        try await sessionLedger.markApplicationObservationTimedOut(for: token)
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The application-observation deadline encountered a monotonic-clock regression.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "The application-observation terminal could not complete safely: \\(error.localizedDescription)",
                            kind: "application_timeout_lifecycle_rejected"
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
''',
"application timeout terminal",
)

replace_once(
'''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.endConnection(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        message = "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture."
        log("sdk_local_ble_dropped", ["generation": String(token.diagnosticGeneration)])
    }
''',
'''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                message = "Observed local-BLE loss could not retire the exact ledger generation. Relaunch Capture before another attempt."
                log("transport_loss_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                message = "Observed local-BLE loss encountered an unrecoverable terminal lifecycle mismatch. Relaunch Capture before another attempt."
                log("transport_loss_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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
''',
"transport terminal fallback",
)

replace_once(
'''    private func invalidateSourceAuthority(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markSourceAuthorityInvalidated(for: token)
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
'''    private func invalidateSourceAuthority(
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
                phase = .failed
                self.message = "Source-authority retirement encountered invalid chronology and could not retire the exact generation. Relaunch Capture."
                log("source_authority_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Source-authority retirement could not close the exact ledger generation. Relaunch Capture."
                log("source_authority_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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
"source terminal fallback",
)

replace_once(
'''    private func invalidateObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markObservationContinuityInvalidated(for: token)
        currentConnectionToken = nil
        localBLESettlementToken = nil
        sdkLocalBLEOnline = false
        driver = nil
        await refreshLedgerSnapshot()
        phase = .failed
        self.message = message
        log(kind, ["generation": String(token.diagnosticGeneration)])
    }

    private func refreshLedgerSnapshot() async {
''',
'''    private func invalidateObservationContinuity(
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
                phase = .failed
                self.message = "Observation-continuity retirement encountered invalid chronology and could not retire the exact generation. Relaunch Capture."
                log("observation_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
        } catch {
            do {
                try await sessionLedger.markInternalLifecycleFailure(for: token)
            } catch {
                phase = .failed
                self.message = "Observation-continuity retirement could not close the exact ledger generation. Relaunch Capture."
                log("observation_terminal_retirement_failed", ["generation": String(token.diagnosticGeneration)])
                return
            }
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
        } catch {
            // Do not discard app ownership when package retirement itself is unproven. Keeping the
            // token blocks generic reset/retry and makes relaunch the only safe recovery.
            phase = .failed
            self.message = "Internal session authority could not be terminally retired. Relaunch Capture before another attempt."
            log("internal_lifecycle_terminal_retirement_failed", [
                "generation": String(token.diagnosticGeneration),
                "requestedKind": kind,
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

    private func refreshLedgerSnapshot() async {
''',
"observation + internal lifecycle terminals",
)

path.write_text(s)
