from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegrityCurrentSourceTests.swift"

PROPS_OLD = '''    private var membershipRequestID = UUID()
    private var acceptsViewScopedMembershipRequests = false
    private var officialConnectionRequestID = UUID()
'''
PROPS_NEW = '''    private var membershipRequestID = UUID()
    private var acceptsViewScopedMembershipRequests = false
    private var officialConnectionRequestID = UUID()
    private var foregroundIntegrityRequiresRelaunch = false
    private var foregroundRetirementToken: TuyaReadOnlyConnectionToken?
'''

ACTIVATE_OLD = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }
'''
ACTIVATE_NEW = '''    func activateMembershipRequestsForView() {
        guard !foregroundIntegrityRequiresRelaunch else { return }
        acceptsViewScopedMembershipRequests = true
    }
'''

EXIT_TOKEN_OLD = '''        if let token = currentConnectionToken {
            phase = .failed
'''
EXIT_TOKEN_NEW = '''        if let token = currentConnectionToken {
            // Foreground loss owns continuity retirement for this exact generation. If SwiftUI also
            // tears the view down, do not race a second internal-lifecycle terminal against it.
            if foregroundRetirementToken == token {
                phase = .failed
                log("view_exit_joined_foreground_retirement", ["generation": String(token.diagnosticGeneration)])
                return
            }
            phase = .failed
'''

FOREGROUND = '''    func appDidLoseForeground() {
        // Scene phase can emit both inactive and background. Snapshot the first live view grant so
        // one foreground transition cannot launch duplicate terminal retirement work.
        let hadViewAuthority = acceptsViewScopedMembershipRequests
        acceptsViewScopedMembershipRequests = false

        // Membership proof is screen-lifetime authority. Revoke it before issued async grants or
        // transport state are examined, matching the accepted Secure Link exit ordering.
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
            foregroundIntegrityRequiresRelaunch = true
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Relaunch Capture and start a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                foregroundIntegrityRequiresRelaunch = true
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        foregroundIntegrityRequiresRelaunch = true
        foregroundRetirementToken = token
        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch Capture before another authenticated attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch Capture before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // Keep the controller alive through the finite exact-token terminal, just as the accepted
        // view-exit path does. Render/lifecycle loss must not cancel evidence retirement.
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


def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "func appDidLoseForeground()" in source or "foregroundRetirementToken" in source:
        raise SystemExit("foreground closure already exists; refresh live product")
    source = one(source, PROPS_OLD, PROPS_NEW, "foreground state")
    source = one(source, ACTIVATE_OLD, ACTIVATE_NEW, "view membership activation")
    source = one(source, EXIT_TOKEN_OLD, EXIT_TOKEN_NEW, "view-exit token join")
    marker = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
    source = one(source, marker, FOREGROUND + marker, "foreground method")
    source = one(source, ENV_OLD, ENV_NEW, "scene environment")
    source = one(source, HANDLER_OLD, HANDLER_NEW, "scene observer")
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    required = (
        "private var foregroundIntegrityRequiresRelaunch = false",
        "private var foregroundRetirementToken: TuyaReadOnlyConnectionToken?",
        "guard !foregroundIntegrityRequiresRelaunch else { return }",
        "if foregroundRetirementToken == token",
        "view_exit_joined_foreground_retirement",
        "func appDidLoseForeground()",
        "let hadViewAuthority = acceptsViewScopedMembershipRequests",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "guard hadViewAuthority else { return }",
        "foregroundIntegrityRequiresRelaunch = true",
        "foregroundRetirementToken = token",
        "Task { @MainActor [self] in",
        "invalidateObservationContinuity(",
        "invalidateInternalLifecycle(",
        "@Environment(\\.scenePhase) private var scenePhase",
        ".onChange(of: scenePhase)",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required foreground token missing: {token}")
    start = source.index("func appDidLoseForeground()")
    end = source.index("var privateConfig: Bool", start)
    cleanup = source[start:end]
    for forbidden in ("[weak self]", "recordObservedTransportLoss", "endConnection(", "disconnectBLE("):
        if forbidden in cleanup:
            raise SystemExit(f"foreground loss gained forbidden transport authority: {forbidden}")
    if not TEST.exists():
        raise SystemExit("foreground source regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
