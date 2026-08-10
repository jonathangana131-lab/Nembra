from pathlib import Path
import subprocess

EXPECTED_PARENT = "eee5a96fae1d30796ba5707f0a7f30f4f4d62530"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
parent = subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
if parent != EXPECTED_PARENT:
    raise SystemExit(f"Refusing stale reanchor: expected {EXPECTED_PARENT}, got {parent}")
source = APP.read_text(encoding="utf-8")

old = '''    func consumeCorrelationAsyncInvalidation() {
        guard (phase == .baseline || phase == .scanning),
              correlationProgress?.isSeriesInvalidated == true else { return }
        correlationSession = nil
        failLocally(
            "Bluetooth correlation ended before this window could be sealed because package-owned scanner/Bluetooth authority became unavailable. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }
'''
new = '''    func consumeCorrelationAsyncInvalidation() {
        guard phase == .baseline || phase == .scanning else { return }
        if OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya regained local-BLE ownership while package correlation was active. This correlation window is invalid; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_reacquired_during_target_correlation"
            )
            return
        }
        guard correlationProgress?.isSeriesInvalidated == true else { return }
        correlationSession = nil
        failLocally(
            "Bluetooth correlation ended before this window could be sealed because package-owned scanner/Bluetooth authority became unavailable. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }
'''
if source.count(old) != 1: raise SystemExit("async invalidation block drifted")
source = source.replace(old, new, 1)

anchor = '''        guard let session = correlationSession,
              let progress = session.progress else {
'''
replacement = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            correlationSession?.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya local-BLE ownership is active before this correlation window. The package scanner will not start; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_ownership_blocks_correlation_window"
            )
            return
        }
        guard let session = correlationSession,
              let progress = session.progress else {
'''
if source.count(anchor) != 1: raise SystemExit("window-start anchor drifted")
source = source.replace(anchor, replacement, 1)

anchor = '''        let sealedLabel = correlationWindowLabel
        do {
            let final = try session.finishCurrentWindow()
'''
replacement = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
            session.abandonCurrentWindow()
            correlationSession = nil
            failLocally(
                "Tuya local-BLE ownership appeared before this correlation window could be sealed. The window is invalid; power the scooter OFF, let Tuya local BLE clear, and restart from OFF1.",
                "sdk_local_ble_ownership_invalidates_correlation_window"
            )
            return
        }

        let sealedLabel = correlationWindowLabel
        do {
            let final = try session.finishCurrentWindow()
'''
if source.count(anchor) != 1: raise SystemExit("window-seal anchor drifted")
source = source.replace(anchor, replacement, 1)

anchor = '''        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
        }
'''
replacement = '''        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
'''
if source.count(anchor) != 1: raise SystemExit("guided task anchor drifted")
source = source.replace(anchor, replacement, 1)

for required in (
    "OfficialTuyaFactory.packageCorrelationMayStart",
    "process_tuya_ble_ownership_blocks_scan",
    "let appleNickname = credential.fullName?.nickname",
    'status = "Tuya rejected the Apple-account login (code \\(code)). Exact scooter membership remains locked."',
    "func signOut()",
    "Use a different Tuya account",
    "private var correlationDisplayedWindowOrdinal: Int",
):
    if required not in source: raise SystemExit(f"newer product contract missing: {required}")
for forbidden in ("disconnectBLE", "publishDps(", "queryDps("):
    controller = source[source.index("private final class SecureLinkController"):source.index("private protocol OfficialTuyaDriver")]
    if forbidden in controller: raise SystemExit(f"ownership repair gained transport mutation: {forbidden}")
APP.write_text(source, encoding="utf-8")
