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


def apply() -> None:
    entry = ENTRYPOINT.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")
    if entry.count(APP_OLD) != 1 or APP_NEW in entry:
        raise SystemExit("SmartLife application secret fragment list changed; re-inspect current product")
    if bridge.count(META_OLD) != 1 or META_NEW in bridge:
        raise SystemExit("Tuya metadata secret fragment list changed; re-inspect current product")
    ENTRYPOINT.write_text(entry.replace(APP_OLD, APP_NEW, 1), encoding="utf-8")
    BRIDGE.write_text(bridge.replace(META_OLD, META_NEW, 1), encoding="utf-8")


def verify() -> None:
    entry = ENTRYPOINT.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")
    if entry.count(APP_NEW) != 1 or APP_OLD in entry:
        raise SystemExit("SmartLife session-key fragment repair is not exact and unique")
    if bridge.count(META_NEW) != 1 or META_OLD in bridge:
        raise SystemExit("metadata session-key fragment repair is not exact and unique")
    for test in (APP_TEST, META_TEST):
        if not test.exists() or "sessionkey" not in test.read_text(encoding="utf-8"):
            raise SystemExit(f"session-key source regression is missing from {test}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
