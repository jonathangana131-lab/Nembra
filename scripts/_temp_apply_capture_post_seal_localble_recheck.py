from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()

old = '''                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        guard self.buildIdentity.isAuthoritativeFieldBuild,\n                              self.accountIdentityLeaseIsAuthorized else {'''
new = '''                        try await sessionLedger.sealAcceptedObservation(for: token)\n                        guard let driver = self.driver else {\n                            self.currentConnectionToken = nil\n                            self.localBLESettlementToken = nil\n                            self.sdkLocalBLEOnline = false\n                            self.phase = .failed\n                            self.message = "Tuya local-BLE authority became unavailable while canonical acceptance was sealing. Restart from OFF1; the sealed package chronology is diagnostic only."\n                            self.log("local_ble_authority_unavailable_during_acceptance_seal", [\n                                "generation": String(token.diagnosticGeneration)\n                            ])\n                            return\n                        }\n                        self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)\n                        guard self.sdkLocalBLEOnline else {\n                            self.currentConnectionToken = nil\n                            self.localBLESettlementToken = nil\n                            self.driver = nil\n                            self.phase = .failed\n                            self.message = "Tuya local BLE went offline while canonical acceptance was sealing. Restart from OFF1; no disconnect timestamp or second package terminal is claimed."\n                            self.log("local_ble_offline_during_acceptance_seal", [\n                                "generation": String(token.diagnosticGeneration)\n                            ])\n                            return\n                        }\n                        guard self.buildIdentity.isAuthoritativeFieldBuild,\n                              self.accountIdentityLeaseIsAuthorized else {'''

if source.count(old) != 1:
    raise SystemExit(f"post-seal insertion point count={source.count(old)}")
source = source.replace(old, new, 1)

watchdog_start = source.index("    private func startWatchdog")
watchdog_end = source.index("    private func recordObservedTransportLoss", watchdog_start)
watchdog = source[watchdog_start:watchdog_end]
seal = watchdog.index("try await sessionLedger.sealAcceptedObservation(for: token)")
freeze = watchdog.index("self.sealedAcceptedExport = self.makeExport(", seal)
post_seal = watchdog[seal:freeze]

required = [
    "guard let driver = self.driver",
    "driver.isLocallyConnected(uuid: self.tuyaUUID)",
    "self.sdkLocalBLEOnline = driver.isLocallyConnected(uuid: self.tuyaUUID)",
    "guard self.sdkLocalBLEOnline else",
    "self.phase = .failed",
    "local_ble_offline_during_acceptance_seal",
    "return",
]
for token in required:
    if token not in post_seal:
        raise SystemExit(f"missing post-seal contract token: {token}")

for forbidden in [
    "sessionLedger.endConnection",
    "markAuthenticationFailed",
    "markSourceAuthorityInvalidated",
    "markObservationContinuityInvalidated",
    "markInternalLifecycleFailure",
]:
    if forbidden in post_seal:
        raise SystemExit(f"forbidden second ledger terminal after seal: {forbidden}")

between_seal_and_recheck = post_seal[
    post_seal.index("try await sessionLedger.sealAcceptedObservation(for: token)")
    + len("try await sessionLedger.sealAcceptedObservation(for: token)"):
    post_seal.index("driver.isLocallyConnected(uuid: self.tuyaUUID)")
]
if "await " in between_seal_and_recheck:
    raise SystemExit("actor suspension found before post-seal local-BLE recheck")

path.write_text(source)
