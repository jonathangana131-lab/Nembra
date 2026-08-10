from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

PARENT = "4b41c9ad783f568d0d353acc9f7016a9bd0b64c2"

REPLACEMENTS = [
    (
        """    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n""",
        """    private var membershipRequestID = UUID()\n    private var acceptsViewScopedMembershipRequests = false\n    private var foregroundIntegrityLossHandled = false\n    private var officialConnectionRequestID = UUID()\n""",
    ),
    (
        """    func activateMembershipRequestsForView() {\n        acceptsViewScopedMembershipRequests = true\n    }\n""",
        """    func activateMembershipRequestsForView() {\n        foregroundIntegrityLossHandled = false\n        acceptsViewScopedMembershipRequests = true\n    }\n""",
    ),
    (
        """        officialConnectionRequestID = UUID()\n        watchdog?.cancel()\n        watchdog = nil\n\n        if let token = currentConnectionToken {\n""",
        """        officialConnectionRequestID = UUID()\n        watchdog?.cancel()\n        watchdog = nil\n\n        // Foreground loss already owns the terminal retirement for this view lifetime.\n        // Avoid racing a second terminal task when backgrounding is followed by onDisappear.\n        if foregroundIntegrityLossHandled { return }\n\n        if let token = currentConnectionToken {\n""",
    ),
    (
        """        log(\"target_correlation_abandoned_on_view_exit\")\n    }\n\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n""",
        """        log(\"target_correlation_abandoned_on_view_exit\")\n    }\n\n    func appDidLoseForeground() {\n        guard !foregroundIntegrityLossHandled else { return }\n        foregroundIntegrityLossHandled = true\n\n        // Capture evidence is foreground-only. Close view-scoped account authority and revoke\n        // already-issued asynchronous grants before inspecting any radio/session state.\n        acceptsViewScopedMembershipRequests = false\n        sdkDeviceMembershipVerified = false\n        membershipAccountUID = nil\n        membershipDeviceID = nil\n        membershipRequestID = UUID()\n        membershipBusy = false\n#if canImport(ThingSmartHomeKit)\n        membershipProbe = nil\n#endif\n        officialConnectionRequestID = UUID()\n        watchdog?.cancel()\n        watchdog = nil\n\n        if processCorrelationLease != nil || correlationSession != nil {\n            // Existing helper stops package transport before releasing this controller's lease.\n            abandonPackageCorrelation()\n            phase = .failed\n            message = \"Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence.\"\n            log(\"foreground_integrity_lost_during_target_correlation\")\n            return\n        }\n\n        guard let token = currentConnectionToken else {\n            if phase == .authenticating {\n                // OfficialTuyaFactory.make() permanently retires package correlation for this\n                // process, even if no package generation existed before foreground loss.\n                localBLESettlementToken = nil\n                sdkLocalBLEOnline = false\n                driver = nil\n                phase = .failed\n                message = \"Capture left the foreground during authentication. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed.\"\n                log(\"foreground_integrity_lost_before_observation\")\n            }\n            return\n        }\n\n        let wasObserving = phase == .observing\n        phase = .failed\n        message = wasObserving\n            ? \"Capture left the foreground during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.\"\n            : \"Capture left the foreground before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed.\"\n        log(\n            wasObserving ? \"foreground_integrity_lost_during_observation\" : \"foreground_integrity_lost_before_observation\",\n            [\"generation\": String(token.diagnosticGeneration)]\n        )\n\n        // This finite terminal task must outlive SwiftUI StateObject teardown. Exact-token fencing\n        // prevents a stale retirement from touching a later generation.\n        Task { @MainActor [self] in\n            guard self.currentConnectionToken == token else { return }\n            if wasObserving {\n                await self.invalidateObservationContinuity(\n                    token: token,\n                    message: \"App foreground integrity was lost during authenticated observation. Relaunch Capture before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.\",\n                    kind: \"foreground_integrity_lost_during_observation\"\n                )\n            } else {\n                await self.invalidateInternalLifecycle(\n                    token: token,\n                    message: \"App foreground integrity was lost before authenticated observation. Relaunch Capture before a new stationary read-only attempt; no BLE disconnect is claimed.\",\n                    kind: \"foreground_integrity_lost_before_observation\"\n                )\n            }\n        }\n    }\n\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n""",
    ),
    (
        """    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n\n    private let stageLabels = [\"Target\", \"Secure link\", \"Observe\", \"Seal\"]\n""",
        """    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.scenePhase) private var scenePhase\n\n    private let stageLabels = [\"Target\", \"Secure link\", \"Observe\", \"Seal\"]\n""",
    ),
    (
        """        .task {\n            test.activateMembershipRequestsForView()\n            sdkAccount.bootstrap()\n            if sdkAccount.loggedIn { test.verifySDKMembership() }\n            while !Task.isCancelled {\n""",
        """        .task {\n            if scenePhase == .active {\n                test.activateMembershipRequestsForView()\n            } else {\n                test.appDidLoseForeground()\n            }\n            sdkAccount.bootstrap()\n            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }\n            while !Task.isCancelled {\n""",
    ),
    (
        """        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n""",
        """        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n        .onChange(of: scenePhase) { _, newPhase in\n            if newPhase == .active {\n                test.activateMembershipRequestsForView()\n                if sdkAccount.loggedIn { test.verifySDKMembership() }\n            } else {\n                test.appDidLoseForeground()\n            }\n        }\n        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n""",
    ),
]


def section(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "func appDidLoseForeground()" in source:
        raise SystemExit("foreground-integrity repair already present")
    for old, new in REPLACEMENTS:
        count = source.count(old)
        if count != 1:
            raise SystemExit(f"exact replacement target count was {count}, expected 1: {old[:100]!r}")
        source = source.replace(old, new, 1)
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    cleanup = section(source, "    func appDidLoseForeground() {", "    var privateConfig: Bool")
    view_exit = section(source, "    func abandonCorrelationForViewExit() {", "    func appDidLoseForeground() {")
    view = section(source, "private struct SecureLinkView: View", "    private var hero: some View")

    ordered = [
        "foregroundIntegrityLossHandled = true",
        "acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "membershipRequestID = UUID()",
        "officialConnectionRequestID = UUID()",
        "if processCorrelationLease != nil || correlationSession != nil",
        "guard let token = currentConnectionToken else",
    ]
    offsets = []
    for token in ordered:
        if token not in cleanup:
            raise SystemExit(f"foreground-integrity token missing: {token}")
        offsets.append(cleanup.index(token))
    if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
        raise SystemExit("foreground-integrity revocation ordering is not fail-closed")

    required = [
        "Task { @MainActor [self] in",
        "guard self.currentConnectionToken == token else { return }",
        "invalidateObservationContinuity(",
        "invalidateInternalLifecycle(",
        "Relaunch Capture before a new stationary read-only attempt",
        "@Environment(\\.scenePhase) private var scenePhase",
        ".onChange(of: scenePhase)",
        "if newPhase == .active",
        "test.activateMembershipRequestsForView()",
        "test.appDidLoseForeground()",
    ]
    combined = cleanup + view
    for token in required:
        if token not in combined:
            raise SystemExit(f"foreground-integrity contract missing: {token}")

    if "Task { @MainActor [weak self] in" in cleanup:
        raise SystemExit("foreground-integrity terminal task is weakly retained")
    if "if foregroundIntegrityLossHandled { return }" not in view_exit:
        raise SystemExit("view-exit path can race a second foreground terminal retirement")
    for forbidden in ("recordObservedTransportLoss", "endConnection(", "disconnectBLE", "writeValue", "publishDps", "queryDps"):
        if forbidden in cleanup:
            raise SystemExit(f"foreground loss gained forbidden transport/protocol authority: {forbidden}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
