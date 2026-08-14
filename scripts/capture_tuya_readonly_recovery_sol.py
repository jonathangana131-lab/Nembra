from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_one(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one anchor, found {count}")
    source = source.replace(old, new, 1)


replace_one(
    "Waiting for a genuine application update and the canonical 45-second horizon…",
    "Waiting for repeated same-generation scooter application evidence, including evidence at least 30 seconds after authentication, plus the canonical 45-second observation horizon…",
    "authentication presentation copy",
)

replace_one(
    "    var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict {\n",
    "    var applicationEvidenceSurvivedHistoricalWindow: Bool {\n"
    "        guard let authenticatedAt = ledgerSnapshot.authenticatedAtUptimeNanoseconds,\n"
    "              let latestPayload = ledgerSnapshot.latestApplicationPayloadUptimeNanoseconds,\n"
    "              latestPayload >= authenticatedAt else { return false }\n"
    "        return latestPayload - authenticatedAt >= TuyaAuthenticatedReadOnlyPreflight.minimumPostAuthenticationPayloadSurvivalNanoseconds\n"
    "    }\n\n"
    "    var preflightVerdict: TuyaAuthenticatedReadOnlyPreflight.Verdict {\n",
    "application survival presentation predicate",
)

replace_one(
    'requirementRow("Scooter data received", ready: test.applicationUpdateCount > 0)',
    'requirementRow("Repeated application evidence", ready: test.applicationUpdateCount >= TuyaAuthenticatedReadOnlyPreflight.minimumAuthenticatedApplicationPayloadCount)\n'
    '                        requirementRow("Application evidence stayed live", ready: test.applicationEvidenceSurvivedHistoricalWindow)',
    "observation checklist truth",
)

receipt_anchor = "\n".join([
    "        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {",
    '            log("stale_application_update_ignored", ["generation": String(token.diagnosticGeneration)])',
])
receipt_terminal = "\n".join([
    "        } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached {",
    "            await mirrorAlreadyTerminalIncompleteObservationHorizon(",
    "                token: token,",
    '                message: "Authenticated read-only preflight is incomplete: required repeated application evidence did not become sufficient within the package-owned observation horizon. The package already retired this exact generation; no Bluetooth disconnect is claimed.",',
    '                kind: "application_authenticated_incomplete_readiness_horizon_reached"',
    "            )",
])
replace_one(receipt_anchor, receipt_terminal + "\n" + receipt_anchor, "application incomplete-horizon mirror")

watchdog_anchor = "\n".join([
    "                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.staleConnection {",
    '                    self.log("stale_watchdog_generation_retired", ["generation": String(token.diagnosticGeneration)])',
])
watchdog_terminal = "\n".join([
    "                } catch TuyaAuthenticatedReadOnlySessionLedger.MutationError.incompleteObservationHorizonReached {",
    "                    await self.mirrorAlreadyTerminalIncompleteObservationHorizon(",
    "                        token: token,",
    '                        message: "Authenticated read-only preflight is incomplete: required repeated application evidence did not become sufficient within the package-owned observation horizon. The package already retired this exact generation; no Bluetooth disconnect is claimed.",',
    '                        kind: "session_authenticated_incomplete_readiness_horizon_reached"',
    "                    )",
    "                    return",
])
replace_one(watchdog_anchor, watchdog_terminal + "\n" + watchdog_anchor, "watchdog incomplete-horizon mirror")

helper_anchor = "\n".join([
    "    private func invalidateObservationContinuity(",
    "        token: TuyaReadOnlyConnectionToken,",
])
helper = "\n".join([
    "    /// Mirrors the incomplete-readiness terminal already committed atomically by the package.",
    "    /// The throwing package mutation has revoked callback authority, so this helper performs",
    "    /// app-local cleanup only. It never issues a second ledger terminal, samples liveness, or",
    "    /// manufactures a Bluetooth disconnect or source-loss observation.",
    "    private func mirrorAlreadyTerminalIncompleteObservationHorizon(",
    "        token: TuyaReadOnlyConnectionToken,",
    "        message: String,",
    "        kind: String",
    "    ) async {",
    "        guard currentConnectionToken == token else { return }",
    "        watchdog?.cancel()",
    "        watchdog = nil",
    "        currentConnectionToken = nil",
    "        localBLESettlementToken = nil",
    "        sdkLocalBLEOnline = false",
    "        driver = nil",
    "        await refreshLedgerSnapshot()",
    "        phase = .failed",
    "        self.message = message",
    '        log(kind, ["generation": String(token.diagnosticGeneration)])',
    "    }",
    "",
    "",
])
replace_one(helper_anchor, helper + helper_anchor, "package-terminal app mirror helper")

legacy_start = "\n                if self.applicationUpdateAdmissionsInFlight == 0,\n"
legacy_end = "\n                try? await Task.sleep(for: .seconds(1))"
if source.count(legacy_start) != 1:
    raise SystemExit(f"legacy app-owned timeout: expected exactly one start anchor, found {source.count(legacy_start)}")
start = source.index(legacy_start)
end = source.index(legacy_end, start)
source = source[:start] + source[end:]

for forbidden in (
    "markApplicationObservationTimedOut(for: token)",
    "done: model.applicationUpdateCount > 0",
    "Waiting for a genuine application update",
):
    if forbidden in source:
        raise SystemExit(f"forbidden stale app truth remains: {forbidden}")

path.write_text(source)
