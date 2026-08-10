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
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await invalidateObservationContinuity(
                token: token,
                message: "Application receipt arrived after authenticated observation continuity was already invalid.",
                kind: "application_observation_continuity_invalidated"
            )
''',
'''        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
            await mirrorAlreadyTerminalObservationContinuity(
                token: token,
                message: "Application receipt crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                kind: "application_observation_continuity_invalidated"
            )
''',
"application receipt mirror",
)

replace_once(
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.invalidateObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness exceeded the accepted continuous-observation horizon.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
''',
'''                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                    await self.mirrorAlreadyTerminalObservationContinuity(
                        token: token,
                        message: "Authenticated-session liveness crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                        kind: "session_liveness_continuity_invalidated"
                    )
                    return
''',
"watchdog liveness mirror",
)

replace_once(
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
'''                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.monotonicClockRegressed {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical acceptance sealing encountered a monotonic-clock regression.",
                            kind: "accepted_prefix_seal_clock_regressed"
                        )
                    } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.observationContinuityInvalidated {
                        await self.mirrorAlreadyTerminalObservationContinuity(
                            token: token,
                            message: "Canonical acceptance crossed the package-owned continuous-observation horizon. The package already retired this generation; no disconnect is claimed.",
                            kind: "accepted_prefix_seal_continuity_invalidated"
                        )
                    } catch {
                        await self.invalidateInternalLifecycle(
                            token: token,
                            message: "Canonical readiness sealing violated the current internal session lifecycle: \\(error.localizedDescription)",
                            kind: "accepted_prefix_seal_lifecycle_rejected"
                        )
                    }
''',
"acceptance seal classification",
)

helper = '''    /// Mirrors a terminal continuity verdict already committed by the package mutation that threw
    /// `observationContinuityInvalidated`. That package path clears its current token before
    /// throwing, so calling another ledger terminal here would manufacture a false retirement
    /// failure. This helper changes app-local ownership/presentation only; it does not claim BLE
    /// disconnect, source loss, a new clock receipt, or a second terminal event.
    private func mirrorAlreadyTerminalObservationContinuity(
        token: TuyaReadOnlyConnectionToken,
        message: String,
        kind: String
    ) async {
        guard currentConnectionToken == token else { return }
        watchdog?.cancel()
        watchdog = nil
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
replace_once(
"    private func invalidateObservationContinuity(\n",
helper + "    private func invalidateObservationContinuity(\n",
"mirror helper insertion",
)

path.write_text(s)
