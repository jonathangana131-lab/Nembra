from pathlib import Path
import subprocess

EXPECTED_PARENT = "a480923c9263389923e334fdca0c8df59ad1b822"
APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")

parent = subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
if parent != EXPECTED_PARENT:
    raise SystemExit(f"Refusing stale mid-series BLE ownership materialization: expected {EXPECTED_PARENT}, got {parent}")

source = APP.read_text(encoding="utf-8")

old_consume = '''    func consumeCorrelationAsyncInvalidation() {
        guard (phase == .baseline || phase == .scanning),
              correlationProgress?.isSeriesInvalidated == true else { return }
        correlationSession = nil
        failLocally(
            "Bluetooth correlation ended before this window could be sealed because package-owned scanner/Bluetooth authority became unavailable. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series.",
            "target_correlation_async_invalidated"
        )
    }
'''
new_consume = '''    func consumeCorrelationAsyncInvalidation() {
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
if source.count(old_consume) != 1:
    raise SystemExit("consumeCorrelationAsyncInvalidation source drifted")
source = source.replace(old_consume, new_consume, 1)

start_anchor = '''        guard let session = correlationSession,
              let progress = session.progress else {
'''
start_guard = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
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
if source.count(start_anchor) != 1:
    raise SystemExit("startCurrentCorrelationWindow anchor drifted")
source = source.replace(start_anchor, start_guard, 1)

finish_anchor = '''        let sealedLabel = correlationWindowLabel
        do {
            let final = try session.finishCurrentWindow()
'''
finish_guard = '''        guard !OfficialTuyaFactory.isLocallyConnected(uuid: tuyaUUID) else {
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
if source.count(finish_anchor) != 1:
    raise SystemExit("finishCorrelationWindow anchor drifted")
source = source.replace(finish_anchor, finish_guard, 1)

old_task = '''        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
        }
'''
new_task = '''        .task {
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
'''
if source.count(old_task) != 1:
    raise SystemExit("SecureLinkView task anchor drifted")
source = source.replace(old_task, new_task, 1)

# Preserve current Apple Auth2 + rider-language work while adding only observation-only fencing.
for required in (
    'let appleNickname = credential.fullName?.nickname',
    'status = "Tuya rejected the Apple-account login (code \\(code)). Exact scooter membership remains locked."',
    'One guided setup establishes the account and bound-device context Nembra will use before passive target correlation begins.',
    'func signOut()',
    'Use a different Tuya account',
    'private var correlationDisplayedWindowOrdinal: Int',
):
    if required not in source:
        raise SystemExit(f"current product contract lost during materialization: {required}")

# This repair observes ownership only; it must not gain any transport-control command.
for forbidden in (
    'ThingSmartBLEManager.sharedInstance().disconnectBLE',
    'publishDps(',
    'queryDps(',
):
    if forbidden in source:
        raise SystemExit(f"mid-series ownership repair must stay observation-only: {forbidden}")

APP.write_text(source, encoding="utf-8")
