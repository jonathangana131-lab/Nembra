from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = path.read_text(encoding="utf-8")

begin_start = text.index("private func beginCorrelationSeries()")
begin_end = text.index("func startNextCorrelationWindow()", begin_start)
begin = text[begin_start:begin_end]
scan_anchor = '''        guard currentConnectionToken == nil else {
'''
scan_insert = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            failLocally(
                "Tuya still reports a current local-BLE session for this scooter. Power the scooter OFF and wait for that session to clear, or relaunch Capture. Package-owned correlation will not scan while Tuya still owns local BLE.",
                "existing_sdk_local_ble_ownership_blocks_scan"
            )
            return
        }
'''
if begin.count(scan_anchor) != 1:
    raise SystemExit(f"expected one currentConnectionToken guard inside beginCorrelationSeries, found {begin.count(scan_anchor)}")
if "existing_sdk_local_ble_ownership_blocks_scan" in begin:
    raise SystemExit("cross-controller BLE gate already exists in beginCorrelationSeries")
begin = begin.replace(scan_anchor, scan_insert + scan_anchor, 1)
text = text[:begin_start] + begin + text[begin_end:]

factory_anchor = '''    static func make() -> OfficialTuyaDriver? {
'''
factory_insert = '''    static func isLocallyConnected(uuid: String) -> Bool {
#if canImport(ThingSmartHomeKit) && canImport(NembraTuyaPrivateConfig)
        guard bootstrap(), !uuid.isEmpty else { return false }
        return ThingSmartBLEManager.sharedInstance().deviceStatue(withUUID: uuid)
#else
        return false
#endif
    }

'''
if text.count(factory_anchor) != 1:
    raise SystemExit(f"expected one OfficialTuyaFactory.make anchor, found {text.count(factory_anchor)}")
if "static func isLocallyConnected(uuid: String) -> Bool" in text:
    raise SystemExit("factory local-BLE observation already exists")
text = text.replace(factory_anchor, factory_insert + factory_anchor, 1)

path.write_text(text, encoding="utf-8")
