from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
BRIDGE = ROOT / "NembraApp/Features/Research/TuyaAccountBridge.swift"
APP_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationUpdateSecretRedactionSourceTests.swift"
META_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaMetadataSecretRedactionSourceTests.swift"

APP_OLD = '''    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
    ]
'''
APP_NEW = '''    private static let secretKeyFragments = [
        "localkey",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
    ]
'''
META_OLD = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "seckey", "authkey"]\n'
META_NEW = '            let secretKeyFragments = ["localkey", "accesstoken", "refreshtoken", "sessionkey", "seckey", "authkey"]\n'
APP_TEST_OLD = '        #expect(driver.contains("refreshtoken"))\n        #expect(driver.contains("authkey"))\n'
APP_TEST_NEW = '        #expect(driver.contains("refreshtoken"))\n        #expect(driver.contains("sessionkey"))\n        #expect(driver.contains("authkey"))\n'
APP_PROMISE_OLD = '        #expect(updates.contains("log(\\"tuya_application_update\\", update.merging(["))\n'
APP_PROMISE_NEW = '        #expect(updates.contains("log(\\"tuya_application_update\\", update.merging(["))\n        #expect(source.contains("No account UID, AppKey/AppSecret, password, account token, local_key, session key"))\n'
META_TEST_OLD = '        #expect(body.contains("refreshtoken"))\n        #expect(body.contains("authkey"))\n'
META_TEST_NEW = '        #expect(body.contains("refreshtoken"))\n        #expect(body.contains("sessionkey"))\n        #expect(body.contains("authkey"))\n'
META_LITERAL_OLD = '        #expect(!body.contains("normalized.contains(\\"refresh_token\\")"))\n'
META_LITERAL_NEW = '        #expect(!body.contains("normalized.contains(\\"refresh_token\\")"))\n        #expect(!body.contains("normalized.contains(\\"session_key\\")"))\n'


def replace_exact(path: Path, old: str, new: str, label: str) -> None:
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1 or new in source:
        raise SystemExit(f"{label} changed or already applied: old={source.count(old)} new={new in source}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def apply() -> None:
    replace_exact(ENTRYPOINT, APP_OLD, APP_NEW, "SmartLife secret fragments")
    replace_exact(BRIDGE, META_OLD, META_NEW, "metadata secret fragments")
    replace_exact(APP_TEST, APP_TEST_OLD, APP_TEST_NEW, "application session-key regression")
    replace_exact(APP_TEST, APP_PROMISE_OLD, APP_PROMISE_NEW, "application export-promise coupling")
    replace_exact(META_TEST, META_TEST_OLD, META_TEST_NEW, "metadata session-key regression")
    replace_exact(META_TEST, META_LITERAL_OLD, META_LITERAL_NEW, "metadata normalized-spelling regression")


def verify() -> None:
    entry = ENTRYPOINT.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")
    app_test = APP_TEST.read_text(encoding="utf-8")
    meta_test = META_TEST.read_text(encoding="utf-8")
    if entry.count(APP_NEW) != 1 or APP_OLD in entry:
        raise SystemExit("SmartLife session-key repair is not exact and unique")
    if bridge.count(META_NEW) != 1 or META_OLD in bridge:
        raise SystemExit("metadata session-key repair is not exact and unique")
    if app_test.count('driver.contains("sessionkey")') != 1:
        raise SystemExit("application regression does not uniquely pin sessionkey")
    if 'No account UID, AppKey/AppSecret, password, account token, local_key, session key' not in app_test:
        raise SystemExit("application regression is not coupled to the export promise")
    if meta_test.count('body.contains("sessionkey")') != 1:
        raise SystemExit("metadata regression does not uniquely pin sessionkey")
    if 'normalized.contains(\\"session_key\\")' not in meta_test:
        raise SystemExit("metadata regression does not reject literal session_key classification")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
