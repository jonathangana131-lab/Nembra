from pathlib import Path
import sys

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureAuthorityLossCorrelationEvidenceRetentionSourceTests.swift")


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")

    view_guard = """        guard processCorrelationLease != nil || correlationSession != nil else { return }\n"""
    view_completed = """        if phase == .correlated || phase == .selected {
            // Final-window sealing already retired the package scanner/lease. Revoke only the
            // reusable target grant here; keep the sealed four-window receipts for diagnostics.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "Capture left Secure Link after Bluetooth target correlation. Restart from OFF1; the prior correlated/selected target cannot cross a view-authority boundary, but its sealed correlation receipts remain diagnostic evidence."
            log("target_correlation_abandoned_on_view_exit")
            return
        }

        guard processCorrelationLease != nil || correlationSession != nil else { return }
"""
    source = replace_once(source, view_guard, view_completed, "completed correlation view-exit fence")

    foreground_old = """        if phase == .correlated || phase == .selected {
            // Final-window sealing already retires the package scanner/lease. These phases can
            // therefore hold actionable target authority with no live transport object to inspect.
            // Foreground loss must invalidate that authority explicitly before a retry.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior correlated/selected target cannot cross a foreground-integrity break."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }
"""
    foreground_new = """        if phase == .correlated || phase == .selected {
            // Final-window sealing already retires the package scanner/lease. Revoke only the
            // actionable target grant; the sealed correlation receipts remain legitimate failed-
            // attempt diagnostics until a fresh OFF1 explicitly clears them.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "Capture left the foreground after Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; the prior target cannot cross a foreground-integrity break, but its sealed correlation receipts remain diagnostic evidence."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }
"""
    source = replace_once(source, foreground_old, foreground_new, "completed correlation foreground fence")

    membership_old = """        pendingCorrelatedTargetID = nil
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
"""
    membership_new = """        pendingCorrelatedTargetID = nil
        if phase == .correlated || phase == .selected {
            // Account authority loss revokes target reuse without deleting the completed physical
            // correlation receipts. A later fresh OFF1 is the only allowed evidence-reset boundary.
            pendingCorrelatedTargetID = nil
            selectedID = nil
            targetCorrelationOperatorConfirmed = false
            phase = .failed
            message = "SDK account authority changed after Bluetooth target correlation. Restart from OFF1 after re-verifying exact scooter membership; prior sealed correlation receipts remain diagnostic evidence only."
            log("sdk_membership_invalidated_after_target_correlation")
        }
        if phase == .baseline || phase == .powerOn || phase == .scanning || phase == .correlated {
            abandonPackageCorrelation()
        }
        membershipStatus = "Official SDK login changed. Exact scooter membership must be verified again."
"""
    source = replace_once(source, membership_old, membership_new, "completed correlation membership fence")

    APP.write_text(source, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    test = TEST.read_text(encoding="utf-8")

    controller_start = source.index("private final class SecureLinkController")
    controller_end = source.index("@MainActor\nprivate protocol OfficialTuyaDriver", controller_start)
    controller = source[controller_start:controller_end]

    def section(start: str, end: str, within: str) -> str:
        a = within.index(start)
        b = within.index(end, a + len(start))
        return within[a:b]

    foreground = section("func appDidLoseForeground()", "var privateConfig: Bool", controller)
    foreground_completed = section(
        "if phase == .correlated || phase == .selected",
        "guard let token = currentConnectionToken else",
        foreground,
    )
    view_exit = section("func abandonCorrelationForViewExit()", "func appDidLoseForeground()", controller)
    view_completed = section(
        "if phase == .correlated || phase == .selected",
        "guard processCorrelationLease != nil || correlationSession != nil",
        view_exit,
    )
    membership = section("func invalidateSDKMembership()", "func verifySDKMembership", controller)
    membership_completed = section(
        "if phase == .correlated || phase == .selected",
        "membershipStatus =",
        membership,
    )

    for label, block, required_kind in (
        ("foreground", foreground_completed, "foreground_integrity_lost_after_target_correlation"),
        ("view exit", view_completed, "target_correlation_abandoned_on_view_exit"),
        ("membership", membership_completed, "sdk_membership_invalidated_after_target_correlation"),
    ):
        for needle in (
            "pendingCorrelatedTargetID = nil",
            "selectedID = nil",
            "targetCorrelationOperatorConfirmed = false",
            "phase = .failed",
            required_kind,
            "Restart from OFF1",
        ):
            if needle not in block:
                raise SystemExit(f"{label}: missing completed-correlation invariant: {needle}")
        for forbidden in (
            "resetDiscoverySessionOnly()",
            "correlationProvenance = nil",
            "targetCorrelationMethod = nil",
            "targetCorrelationWindowCount = nil",
            "candidates.removeAll()",
        ):
            if forbidden in block:
                raise SystemExit(f"{label}: sealed evidence erased by completed-correlation path: {forbidden}")

    # Scanner-first retirement remains ahead of the completed-state branch for foreground loss.
    live_transport = foreground.index("if processCorrelationLease != nil || correlationSession != nil")
    completed_state = foreground.index("if phase == .correlated || phase == .selected")
    if live_transport >= completed_state:
        raise SystemExit("foreground completed-state repair weakened live scanner-first retirement")
    if "resetDiscoverySessionOnly()" not in foreground[live_transport:completed_state]:
        raise SystemExit("live foreground correlation no longer performs full scanner-first reset")

    begin = section("private func beginCorrelationSeries()", "func startNextCorrelationWindow()", controller)
    if "resetDiscoverySessionOnly()" not in begin:
        raise SystemExit("fresh OFF1 no longer owns the explicit completed-evidence reset boundary")

    export_builder = section("private func makeExport(exportedAt:", "func prepareExport()", controller)
    for needle in (
        "targetCorrelationMethod: targetCorrelationMethod",
        "targetCorrelationWindowCount: targetCorrelationWindowCount",
        "targetCorrelationOperatorConfirmed: targetCorrelationOperatorConfirmed",
        "targetCorrelationProvenance: correlationProvenance",
        "candidates: candidates",
    ):
        if needle not in export_builder:
            raise SystemExit(f"failed diagnostic export lost correlation evidence field: {needle}")

    if "membershipLossPreservesSealedCorrelationEvidence" not in test:
        raise SystemExit("membership-loss sibling regression was not absorbed")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if mode == "apply":
        apply()
    elif mode == "verify":
        verify()
    else:
        raise SystemExit(f"unknown mode: {mode}")
