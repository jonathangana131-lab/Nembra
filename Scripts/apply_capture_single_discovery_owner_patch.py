from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
s = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    s = s.replace(old, new, 1)

replace_once("@preconcurrency import CoreBluetooth\n", "", "legacy CoreBluetooth import")
replace_once("\nlet CBAdvertisementDataIsConnectableKey = CBAdvertisementDataIsConnectable\n", "\n", "legacy advertisement key alias")
replace_once("    static let fd50 = CBUUID(string: \"FD50\")\n", "", "legacy FD50 scanner key")
replace_once("    private var central: CBCentralManager!\n", "", "legacy app central manager")
replace_once("    private var baseline = Set<UUID>()\n", "", "legacy baseline scanner state")
replace_once("        central = CBCentralManager(delegate: self, queue: .main)\n", "", "legacy central init")

stop_count = s.count("        central.stopScan()\n")
if stop_count != 4:
    raise SystemExit(f"legacy stopScan: expected 4 matches, found {stop_count}")
s = s.replace("        central.stopScan()\n", "")

replace_once("        baseline.removeAll()\n", "", "legacy baseline reset")

start = s.find("    private static func hasTuyaCompanyID")
end_marker = "\n@MainActor\nprivate protocol OfficialTuyaDriver"
end = s.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit("legacy advertisement scanner block not found")
block = s[start:end]
required = [
    "private static func hasTuyaCompanyID",
    "private func updateCandidate",
    "CBCentralManagerDelegate",
    "didDiscover peripheral",
    "CBAdvertisementDataManufacturerDataKey",
]
for needle in required:
    if needle not in block:
        raise SystemExit(f"legacy scanner block missing expected marker: {needle}")
# The block starts inside SecureLinkController and includes its closing brace plus
# the legacy delegate extension. Preserve exactly one controller closing brace.
s = s[:start] + "}\n" + s[end:]

for forbidden in [
    "CBCentralManager",
    "CBCentralManagerDelegate",
    "central.stopScan",
    "central.scanForPeripherals",
    "CBAdvertisementDataServiceUUIDsKey",
    "CBAdvertisementDataManufacturerDataKey",
    "CBAdvertisementDataIsConnectableKey",
    "private func updateCandidate",
]:
    if forbidden in s:
        raise SystemExit(f"forbidden legacy scanner marker remains: {forbidden}")

if "PassiveBluetoothPowerCycleObservationSession" not in s:
    raise SystemExit("package-owned correlation session unexpectedly missing")

path.write_text(s)
