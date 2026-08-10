from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegrityCurrentSourceTests.swift"

STATUS_OLD = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
'''
STATUS_NEW = '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Exact scooter membership authority was revoked when Capture left the foreground; it must be freshly verified before use."
        membershipRequestID = UUID()
'''

TASK_OLD = '''        .task {
            test.activateMembershipRequestsForView()
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
'''
TASK_NEW = '''        .task {
            test.activateMembershipRequestsForView()
            if scenePhase != .active {
                test.appDidLoseForeground()
            }
            sdkAccount.bootstrap()
            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
'''


def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    prefix, cleanup, suffix = source[:start], source[start:end], source[end:]
    cleanup = one(cleanup, STATUS_OLD, STATUS_NEW, "foreground membership status")
    source = prefix + cleanup + suffix
    source = one(source, TASK_OLD, TASK_NEW, "initial scene gate")
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    cleanup = source[start:end]
    if 'membershipStatus = "Exact scooter membership authority was revoked when Capture left the foreground; it must be freshly verified before use."' not in cleanup:
        raise SystemExit("foreground membership status is not truthful")
    if "if scenePhase != .active {\n                test.appDidLoseForeground()" not in source:
        raise SystemExit("initial task does not close non-active scene admission")
    if "if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }" not in source:
        raise SystemExit("initial membership verification is not scene-active gated")
    if not TEST.exists():
        raise SystemExit("foreground regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
