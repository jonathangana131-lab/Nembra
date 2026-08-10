from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaForegroundStationaryRecoverySourceTests.swift"

ACTIVATE_OLD = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }
'''
ACTIVATE_NEW = '''    func activateMembershipRequestsForView() {
        guard phase != .failed else { return }
        acceptsViewScopedMembershipRequests = true
    }
'''

FOREGROUND = '''    func appDidLoseForeground() {
        // Scene phase can emit both inactive and background. Capture the first live view grant so
        // the same foreground loss cannot launch duplicate terminal retirement tasks.
        let hadViewAuthority = acceptsViewScopedMembershipRequests
        acceptsViewScopedMembershipRequests = false

        // Membership proof is view-scoped authority. Revoke it synchronously before rotating any
        // already-issued async request generation or inspecting package/Tuya transport state.
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        guard hadViewAuthority else { return }

        if processCorrelationLease != nil || correlationSession != nil {
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Relaunch Capture and start a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch Capture before another authenticated attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // Strongly retain the controller for this finite exact-token terminal, matching view-exit
        // retirement: StateObject destruction must not silently skip package lifecycle closure.
        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch Capture before another authenticated attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

'''

ENV_OLD = '''    @State private var showEngineeringDetails = false
    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize
'''
ENV_NEW = '''    @State private var showEngineeringDetails = false
    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\\.scenePhase) private var scenePhase
'''
HANDLER_OLD = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''
HANDLER_NEW = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                test.appDidLoseForeground()
            } else {
                test.activateMembershipRequestsForView()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''

COPY = {
    "Source authority changed while canonical acceptance was sealing. Restart from OFF1; the sealed package chronology is diagnostic only.": "Source authority changed while canonical acceptance was sealing. Relaunch Capture before a new stationary read-only attempt; the sealed package chronology is diagnostic only.",
    "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.": "Tuya local-BLE authority became unavailable after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
    "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Restart from OFF1; no disconnect time is inferred.": "Tuya local-BLE authority was no longer current after canonical acceptance sealed. Relaunch Capture before a new stationary read-only attempt; no disconnect time is inferred.",
    "Authenticated session produced no application update before the observation deadline. Export diagnostics; do not repeat the ride capture.": "Authenticated session produced no application update before the observation deadline. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
    "Tuya's current local-BLE session ended before acceptance. Export diagnostics; do not repeat the outdoor ride capture.": "Tuya's current local-BLE session ended before acceptance. Export diagnostics; relaunch Capture before any new stationary read-only attempt.",
    "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1 rather than rebuilding accepted evidence from mutable post-seal state.": "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Relaunch Capture before a new stationary read-only attempt; do not rebuild accepted evidence from mutable post-seal state.",
}

def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return source.replace(old, new, 1)

def apply() -> None:
    source = ENTRYPOINT.read_text()
    if "func appDidLoseForeground()" in source or "@Environment(\\.scenePhase) private var scenePhase" in source:
        raise SystemExit("foreground repair already present; refresh product instead")
    source = one(source, ACTIVATE_OLD, ACTIVATE_NEW, "membership activation")
    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    source = one(source, marker, FOREGROUND + marker, "foreground method insertion")
    source = one(source, ENV_OLD, ENV_NEW, "scene environment")
    source = one(source, HANDLER_OLD, HANDLER_NEW, "scene handler")
    for old, new in COPY.items():
        source = one(source, old, new, "stationary recovery")
    ENTRYPOINT.write_text(source)

def verify() -> None:
    source = ENTRYPOINT.read_text()
    for token in (
        "func appDidLoseForeground()", "let hadViewAuthority = acceptsViewScopedMembershipRequests",
        "sdkDeviceMembershipVerified = false", "membershipAccountUID = nil", "membershipDeviceID = nil",
        "guard hadViewAuthority else { return }", "Task { @MainActor [self] in",
        "@Environment(\\.scenePhase) private var scenePhase", ".onChange(of: scenePhase)",
        "Export diagnostics; relaunch Capture before any new stationary read-only attempt."
    ):
        if token not in source: raise SystemExit(f"missing token: {token}")
    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    cleanup = source[start:end]
    for forbidden in ("[weak self]", "recordObservedTransportLoss", "endConnection(", "disconnectBLE("):
        if forbidden in cleanup: raise SystemExit(f"foreground repair contains forbidden authority: {forbidden}")
    for stale in ("do not repeat the ride capture", "do not repeat the outdoor ride capture", "Source authority changed while canonical acceptance was sealing. Restart from OFF1", "Accepted diagnostics cannot be exported because the immutable accepted artifact is unavailable. Restart from OFF1"):
        if stale in source: raise SystemExit(f"stale recovery remains: {stale}")
    if not TEST.exists(): raise SystemExit("source regression missing")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
