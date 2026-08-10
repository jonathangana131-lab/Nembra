from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
SOURCE_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    app = ENTRYPOINT.read_text()

    app = replace_once(
        app,
        """    func activateMembershipRequestsForView() {\n        // A fast inactive -> active transition must not reset the duplicate-retirement fence\n        // while the exact authenticated generation from foreground loss is still terminalizing.\n        guard currentConnectionToken == nil else { return }\n        foregroundIntegrityLossHandled = false\n        acceptsViewScopedMembershipRequests = true\n    }\n""",
        """    func activateMembershipRequestsForView() {\n        // A fast inactive -> active transition must not reset the duplicate-retirement fence\n        // while an authenticated generation is terminalizing or after the one-shot official Tuya\n        // handoff has retired package correlation for this process. Post-handoff recovery is relaunch.\n        guard currentConnectionToken == nil,\n              OfficialTuyaFactory.packageCorrelationMayStart else { return }\n        foregroundIntegrityLossHandled = false\n        acceptsViewScopedMembershipRequests = true\n    }\n""",
        "view membership reactivation fence",
    )

    app = replace_once(
        app,
        """    func appDidLoseForeground() {\n        guard !foregroundIntegrityLossHandled else { return }\n        foregroundIntegrityLossHandled = true\n""",
        """    func appDidLoseForeground() {\n        // A sealed accepted artifact is immutable historical evidence. Foreground loss after seal\n        // must not revoke or rewrite the already-accepted subject merely for presentation lifecycle.\n        guard phase != .accepted else { return }\n        guard !foregroundIntegrityLossHandled else { return }\n        foregroundIntegrityLossHandled = true\n""",
        "sealed accepted foreground preservation",
    )

    app = replace_once(
        app,
        """        if processCorrelationLease != nil || correlationSession != nil {\n            // Existing helper stops package transport before releasing this controller's lease.\n            abandonPackageCorrelation()\n            phase = .failed\n            message = \"Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence.\"\n            log(\"foreground_integrity_lost_during_target_correlation\")\n            return\n        }\n\n        guard let token = currentConnectionToken else {\n""",
        """        if processCorrelationLease != nil || correlationSession != nil {\n            // Existing helper stops package transport before releasing this controller's lease.\n            abandonPackageCorrelation()\n            phase = .failed\n            message = \"Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence.\"\n            log(\"foreground_integrity_lost_during_target_correlation\")\n            return\n        }\n\n        if phase == .correlated || phase == .selected {\n            // The finite scanners are already retired by this point, but their correlation result\n            // is still mutable current-attempt authority. It may not cross a foreground boundary.\n            resetDiscoverySessionOnly()\n            phase = .failed\n            message = \"Capture left the foreground after Bluetooth target correlation. Return to Capture, re-verify this scooter in the current Tuya account, and restart from OFF1; prior correlation/selection is not reusable evidence.\"\n            log(\"foreground_integrity_lost_after_target_correlation\")\n            return\n        }\n\n        guard let token = currentConnectionToken else {\n""",
        "sealed correlation foreground invalidation",
    )
    ENTRYPOINT.write_text(app)

    test = SOURCE_TEST.read_text()
    test = replace_once(
        test,
        """        let retiredGenerationGate = try requiredOffset(\n            containing: \"guard currentConnectionToken == nil else { return }\",\n            in: activation\n        )\n        let resetForegroundFence = try requiredOffset(\n            containing: \"foregroundIntegrityLossHandled = false\",\n            in: activation\n        )\n        let reopenAdmission = try requiredOffset(\n            containing: \"acceptsViewScopedMembershipRequests = true\",\n            in: activation\n        )\n        #expect(retiredGenerationGate < resetForegroundFence)\n        #expect(resetForegroundFence < reopenAdmission)\n""",
        """        let retiredGenerationGate = try requiredOffset(\n            containing: \"guard currentConnectionToken == nil,\",\n            in: activation\n        )\n        let processHandoffGate = try requiredOffset(\n            containing: \"OfficialTuyaFactory.packageCorrelationMayStart\",\n            in: activation\n        )\n        let resetForegroundFence = try requiredOffset(\n            containing: \"foregroundIntegrityLossHandled = false\",\n            in: activation\n        )\n        let reopenAdmission = try requiredOffset(\n            containing: \"acceptsViewScopedMembershipRequests = true\",\n            in: activation\n        )\n        #expect(retiredGenerationGate < processHandoffGate)\n        #expect(processHandoffGate < resetForegroundFence)\n        #expect(resetForegroundFence < reopenAdmission)\n""",
        "reactivation test contract",
    )

    test = replace_once(
        test,
        """        let correlationCheck = try requiredOffset(\n            containing: \"if processCorrelationLease != nil || correlationSession != nil\",\n            in: cleanup\n        )\n        let tokenCheck = try requiredOffset(\n            containing: \"guard let token = currentConnectionToken else\",\n            in: cleanup\n        )\n""",
        """        let correlationCheck = try requiredOffset(\n            containing: \"if processCorrelationLease != nil || correlationSession != nil\",\n            in: cleanup\n        )\n        let sealedCorrelationCheck = try requiredOffset(\n            containing: \"if phase == .correlated || phase == .selected\",\n            in: cleanup\n        )\n        let tokenCheck = try requiredOffset(\n            containing: \"guard let token = currentConnectionToken else\",\n            in: cleanup\n        )\n""",
        "correlated-selected test ordering",
    )

    test = replace_once(
        test,
        """        #expect(membershipRevoke < officialRevoke)\n        #expect(officialRevoke < correlationCheck)\n        #expect(officialRevoke < tokenCheck)\n        #expect(cleanup.contains(\"membershipBusy = false\"))\n        #expect(cleanup.contains(\"membershipProbe = nil\"))\n        #expect(cleanup.contains(\"watchdog?.cancel()\"))\n        #expect(cleanup.contains(\"foregroundIntegrityLossHandled = true\"))\n""",
        """        #expect(membershipRevoke < officialRevoke)\n        #expect(officialRevoke < correlationCheck)\n        #expect(correlationCheck < sealedCorrelationCheck)\n        #expect(sealedCorrelationCheck < tokenCheck)\n        #expect(cleanup.contains(\"membershipBusy = false\"))\n        #expect(cleanup.contains(\"membershipProbe = nil\"))\n        #expect(cleanup.contains(\"watchdog?.cancel()\"))\n        let acceptedPreservationGate = try requiredOffset(\n            containing: \"guard phase != .accepted else { return }\",\n            in: cleanup\n        )\n        let markForegroundLossHandled = try requiredOffset(\n            containing: \"foregroundIntegrityLossHandled = true\",\n            in: cleanup\n        )\n        #expect(acceptedPreservationGate < markForegroundLossHandled)\n        #expect(cleanup.contains(\"resetDiscoverySessionOnly()\"))\n        #expect(cleanup.contains(\"foreground_integrity_lost_after_target_correlation\"))\n""",
        "accepted and correlated authority test contract",
    )
    SOURCE_TEST.write_text(test)


def verify() -> None:
    app = ENTRYPOINT.read_text()
    test = SOURCE_TEST.read_text()
    required_app = [
        "guard currentConnectionToken == nil,\n              OfficialTuyaFactory.packageCorrelationMayStart else { return }",
        "guard phase != .accepted else { return }",
        "if phase == .correlated || phase == .selected",
        "resetDiscoverySessionOnly()",
        "foreground_integrity_lost_after_target_correlation",
        "Task { @MainActor [self] in",
    ]
    for token in required_app:
        if token not in app:
            raise SystemExit(f"missing app invariant: {token}")
    if "guard currentConnectionToken == nil else { return }" in app[app.index("func activateMembershipRequestsForView()"):app.index("func abandonCorrelationForViewExit()")]:
        raise SystemExit("old token-only reactivation gate remains")
    required_test = [
        "OfficialTuyaFactory.packageCorrelationMayStart",
        "guard phase != .accepted else { return }",
        "if phase == .correlated || phase == .selected",
        "foreground_integrity_lost_after_target_correlation",
    ]
    for token in required_test:
        if token not in test:
            raise SystemExit(f"missing source-test invariant: {token}")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"apply", "verify"}:
        raise SystemExit("usage: materialize_capture_foreground_authority_r4.py apply|verify")
    globals()[sys.argv[1]]()
