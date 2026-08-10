from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaFreshTargetAndAcquisitionTerminalSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


app = APP.read_text()

app = replace_once(
    app,
    "    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }",
    "    var fieldBuildIsAuthoritative: Bool { buildIdentity.isAuthoritativeFieldBuild }\n    var fieldBuildIdentifier: String { buildIdentity.buildIdentifier }",
    "field build label projection",
)
app = replace_once(
    app,
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? "Authoritative" : "Not authoritative")',
    '            LabeledContent("Field build", value: test.fieldBuildIsAuthoritative ? test.fieldBuildIdentifier : "Not authoritative")',
    "show exact field build label",
)

# A source-identity change invalidates the recipe ordering that authorized the pending/selected
# local target. Preserve the completed correlation result for diagnostics but revoke promotion.
app = replace_once(
    app,
    "        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        central.stopScan()",
    "        correlationSession?.abandonCurrentWindow()\n        correlationSession = nil\n        pendingCorrelatedTargetID = nil\n        selectedID = nil\n        central.stopScan()",
    "revoke local target promotion on membership loss",
)

# Mint the app's exact token owner immediately after beginConnection so even an auth-start clock
# failure can use the package's no-clock chronology terminal and cannot strand hidden authority.
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
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authentication-start chronology failed closed before Tuya BLE ownership: \(error.localizedDescription)",
                        kind: "session_auth_start_chronology_rejected"
                    )
                    return
                }
                await self.refreshLedgerSnapshot()''',
    "auth-start token ownership",
)

# Application callback monotonic failure must use the terminal that deliberately takes no new
# clock receipt. Other chronology failures retain the observation-continuity classification.
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
        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
            await invalidateChronologyIntegrity(
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
    "application callback clock terminal",
)

app = replace_once(
    app,
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
                    await self.invalidateChronologyIntegrity(
                        token: token,
                        message: "Authenticated observation chronology was invalidated by a monotonic-clock regression.",
                        kind: "observation_clock_regressed"
                    )
                    return
                }''',
    "watchdog explicit clock regression terminal",
)

app = replace_once(
    app,
    '''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    do {
                        try await sessionLedger.markObservationContinuityInvalidated(for: token)
                    } catch {}
                    self.currentConnectionToken = nil
                    await self.refreshLedgerSnapshot()
                    self.failLocally("Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.", "observation_poll_gap_exceeded")
                    return
                }''',
    '''                guard gap <= Self.maximumObservationPollGapNanoseconds else {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated observation continuity was interrupted; the gap is not evidence that BLE disconnected.",
                        kind: "observation_poll_gap_exceeded"
                    )
                    return
                }''',
    "watchdog gap terminal helper",
)

app = replace_once(
    app,
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness chronology failed closed: \(error.localizedDescription)",
                        kind: "session_liveness_rejected"
                    )
                    return
                }''',
    '''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.noActiveConnection {
                    self.log("sealed_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])
                    return
                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                    await self.invalidateChronologyIntegrity(
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
                }''',
    "watchdog mutation clock terminal",
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
    '''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateChronologyIntegrity(
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
    "seal clock terminal",
)

app = replace_once(
    app,
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
                        await self.invalidateChronologyIntegrity(
                            token: token,
                            message: "Application-observation deadline could not be sealed because the monotonic clock regressed.",
                            kind: "application_timeout_clock_regressed"
                        )
                        return
                    } catch {
                        await self.invalidateObservationContinuity(
                            token: token,
                            message: "Application-observation deadline could not be sealed: \(error.localizedDescription)",
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
                }''',
    "application timeout terminal fallback",
)

# Every terminal that normally samples the clock falls back to the no-clock retirement if that
# sample cannot be trusted. This keeps package/app token ownership aligned on all exit paths.
app = replace_once(
    app,
    '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        try? await sessionLedger.endConnection(for: token)
        currentConnectionToken = nil''',
    '''    private func recordObservedTransportLoss(token: TuyaReadOnlyConnectionToken) async {
        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.endConnection(for: token)
        } catch {
            try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        }
        currentConnectionToken = nil''',
    "transport loss fallback",
)
app = replace_once(
    app,
    '''        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markSourceAuthorityInvalidated(for: token)
        currentConnectionToken = nil''',
    '''        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markSourceAuthorityInvalidated(for: token)
        } catch {
            try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        }
        currentConnectionToken = nil''',
    "source terminal fallback",
)
app = replace_once(
    app,
    '''        guard currentConnectionToken == token else { return }
        try? await sessionLedger.markObservationContinuityInvalidated(for: token)
        currentConnectionToken = nil''',
    '''        guard currentConnectionToken == token else { return }
        do {
            try await sessionLedger.markObservationContinuityInvalidated(for: token)
        } catch {
            try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)
        }
        currentConnectionToken = nil''',
    "continuity terminal fallback",
)

APP.write_text(app)

test = TEST.read_text()
needle = '''        #expect(app.contains("sessionLedger.markChronologyIntegrityInvalidated(for: token)"))
        #expect(app.contains("localBLESettlementToken"))'''
replacement = '''        #expect(app.contains("sessionLedger.markChronologyIntegrityInvalidated(for: token)"))
        #expect(app.contains("session_auth_start_chronology_rejected"))
        #expect(app.contains("application_update_clock_regressed"))
        #expect(app.contains("observation_clock_regressed"))
        #expect(app.contains("session_liveness_clock_regressed"))
        #expect(app.contains("accepted_prefix_seal_clock_regressed"))
        #expect(app.contains("application_timeout_clock_regressed"))
        #expect(app.contains("localBLESettlementToken"))'''
if needle not in test:
    raise SystemExit("clock-retirement test marker missing")
TEST.write_text(test.replace(needle, replacement, 1))

final = APP.read_text()
for marker in (
    "self.currentConnectionToken = token\n                do {\n                    try await self.sessionLedger.markAuthenticationStarted",
    "application_update_clock_regressed",
    "observation_clock_regressed",
    "session_liveness_clock_regressed",
    "accepted_prefix_seal_clock_regressed",
    "application_timeout_clock_regressed",
    "try? await sessionLedger.markChronologyIntegrityInvalidated(for: token)",
    "test.fieldBuildIdentifier",
):
    if marker not in final:
        raise SystemExit(f"missing hardened marker: {marker}")
print("V14 Capture no-clock terminal hardening applied")
