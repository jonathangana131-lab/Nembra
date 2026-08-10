from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()
old = '''        guard currentConnectionToken == nil else {
            failLocally(
                "A prior authenticated generation has not been terminally retired. Relaunch Capture before starting another attempt.",
                "active_generation_blocks_discovery_reset"
            )
            return
        }
'''
new = '''        guard currentConnectionToken == nil else {
            if let token = currentConnectionToken {
                Task { @MainActor [weak self] in
                    await self?.invalidateInternalLifecycle(
                        token: token,
                        message: "A prior authenticated generation unexpectedly still owned session authority when OFF1 restart was requested. It was retired before discovery reset.",
                        kind: "active_generation_blocks_discovery_reset"
                    )
                }
            }
            return
        }
'''
count = source.count(old)
if count != 1:
    raise SystemExit(f"expected one OFF1 active-generation guard, found {count}")
source = source.replace(old, new, 1)

start = source.index("    private func beginCorrelationSeries()")
end = source.index("    func startNextCorrelationWindow()", start)
section = source[start:end]
for needle in [
    "currentConnectionToken == nil",
    "invalidateInternalLifecycle(",
    "active_generation_blocks_discovery_reset",
    "resetDiscoverySessionOnly()",
    "PassiveBluetoothPowerCycleObservationSession",
]:
    if needle not in section:
        raise SystemExit(f"missing post-patch invariant: {needle}")
for forbidden in ["markAuthenticated(for:", "recordApplicationUpdate", "endConnection(for:"]:
    if forbidden in section:
        raise SystemExit(f"ordinary correlation restart manufactured session evidence: {forbidden}")

path.write_text(source)
