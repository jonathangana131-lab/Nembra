from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureMembershipCorrelationAuthorityRevocationSourceTests.swift")


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old = '''        pendingCorrelatedTargetID = nil
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
    new = '''        pendingCorrelatedTargetID = nil
        if phase == .correlated || phase == .selected {
            // Final-window sealing already retired package scanning. Account authority loss must
            // revoke target reuse without deleting the completed physical-correlation receipts.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "SDK account authority changed after Bluetooth target correlation. Restart from OFF1 after re-verifying exact scooter membership; completed correlation evidence remains available for diagnostics."
            log("sdk_membership_invalidated_after_target_correlation")
        }
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
'''
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"expected exactly one membership invalidation seam, found {count}")
    APP.write_text(source.replace(old, new, 1), encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    controller_start = source.index("private final class SecureLinkController")
    controller_end = source.index("@MainActor\nprivate protocol OfficialTuyaDriver", controller_start)
    controller = source[controller_start:controller_end]
    a = controller.index("func invalidateSDKMembership()")
    b = controller.index("func verifySDKMembership", a)
    invalidation = controller[a:b]
    c = invalidation.index("if phase == .correlated || phase == .selected")
    d = invalidation.index("membershipStatus =", c)
    completed = invalidation[c:d]

    for needle in (
        "pendingCorrelatedTargetID = nil",
        "selectedID = nil",
        "targetCorrelationOperatorConfirmed = false",
        "phase = .failed",
        "sdk_membership_invalidated_after_target_correlation",
        "Restart from OFF1",
    ):
        if needle not in completed:
            raise SystemExit(f"completed membership-loss branch missing: {needle}")

    for forbidden in (
        "resetDiscoverySessionOnly()",
        "correlationProvenance = nil",
        "targetCorrelationMethod = nil",
        "targetCorrelationWindowCount = nil",
        "candidates.removeAll()",
    ):
        if forbidden in completed:
            raise SystemExit(f"membership-loss branch erases sealed evidence: {forbidden}")

    if "if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated" not in invalidation:
        raise SystemExit("live package-correlation retirement branch disappeared")
    if "abandonPackageCorrelation()" not in invalidation:
        raise SystemExit("live package-correlation retirement helper disappeared")

    begin_start = controller.index("private func beginCorrelationSeries()")
    begin_end = controller.index("func startNextCorrelationWindow()", begin_start)
    begin = controller[begin_start:begin_end]
    if "resetDiscoverySessionOnly()" not in begin:
        raise SystemExit("fresh OFF1 no longer owns the retained-evidence reset boundary")

    if not TEST.exists() or "membershipLossRevokesTargetGrantAndPreservesEvidence" not in TEST.read_text(encoding="utf-8"):
        raise SystemExit("membership correlation authority regression missing")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(f"unknown mode: {mode}")
