from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor changed: expected 1, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "func appDidLoseForeground()" in source:
        raise SystemExit("foreground integrity handler already exists; re-inspect live product")

    source = replace_once(
        source,
        "    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n",
        "    private var acceptsViewScopedMembershipRequests = false\n    private var foregroundIntegrityIsActive = true\n    private var officialConnectionRequestID = UUID()\n",
        "foreground state",
    )

    anchor = '''        log("target_correlation_abandoned_on_view_exit")
    }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
'''
    foreground = '''        log("target_correlation_abandoned_on_view_exit")
    }

    func appDidLoseForeground() {
        // Scene inactivity is a first-class evidence break. Revoke request/proof authority before
        // looking at radio/session state so no delayed callback can promote an off-screen attempt.
        guard foregroundIntegrityIsActive else { return }
        foregroundIntegrityIsActive = false
        acceptsViewScopedMembershipRequests = false
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

        if processCorrelationLease != nil || correlationSession != nil {
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // This finite terminal operation is authority-critical. Strongly retain the controller until
        // the exact package generation reaches its terminal, matching view-exit lifetime semantics.
        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }

    func appDidBecomeActiveForView() {
        // Re-entry restores only permission to ask the official account for fresh membership proof.
        // It never restores a revoked proof, scanner, BLE owner, package token or evidence clock.
        foregroundIntegrityIsActive = true
        acceptsViewScopedMembershipRequests = true
    }

    var privateConfig: Bool { OfficialTuyaFactory.configured }
'''
    source = replace_once(source, anchor, foreground, "foreground handler insertion")

    source = replace_once(
        source,
        "    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
        "    @State private var showEngineeringDetails = false\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.scenePhase) private var scenePhase\n",
        "scene phase environment",
    )

    old_task = '''        .task {
            test.activateMembershipRequestsForView()
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
'''
    new_task = '''        .task {
            if scenePhase == .active {
                test.appDidBecomeActiveForView()
            } else {
                test.appDidLoseForeground()
            }
            sdkAccount.bootstrap()
            if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
                test.consumeCorrelationAsyncInvalidation()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                test.appDidBecomeActiveForView()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            } else {
                test.appDidLoseForeground()
            }
        }
'''
    source = replace_once(source, old_task, new_task, "Secure Link lifecycle modifiers")
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    controller_start = source.index("private final class SecureLinkController")
    controller_end = source.index("@MainActor\nprivate protocol OfficialTuyaDriver", controller_start)
    controller = source[controller_start:controller_end]
    loss_start = controller.index("func appDidLoseForeground()")
    active_start = controller.index("func appDidBecomeActiveForView()", loss_start)
    private_config = controller.index("var privateConfig: Bool", active_start)
    loss = controller[loss_start:active_start]
    active = controller[active_start:private_config]

    required_loss = (
        "guard foregroundIntegrityIsActive else { return }",
        "foregroundIntegrityIsActive = false",
        "acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "membershipRequestID = UUID()",
        "membershipBusy = false",
        "membershipProbe = nil",
        "officialConnectionRequestID = UUID()",
        "watchdog?.cancel()",
        "abandonPackageCorrelation()",
        "Task { @MainActor [self] in",
        "self.currentConnectionToken == token",
        "invalidateObservationContinuity(",
        "invalidateInternalLifecycle(",
    )
    for token in required_loss:
        if token not in loss:
            raise SystemExit(f"foreground loss contract missing: {token}")
    if loss.index("acceptsViewScopedMembershipRequests = false") > loss.index("membershipRequestID = UUID()"):
        raise SystemExit("foreground loss must close request admission before revoking issued membership callbacks")
    if loss.index("membershipRequestID = UUID()") > loss.index("if processCorrelationLease != nil || correlationSession != nil"):
        raise SystemExit("foreground loss must revoke membership callbacks before transport inspection")
    for forbidden in ("releasePackageCorrelationLease()", "recordObservedTransportLoss", "endConnection", "disconnect", "publishDps", "writeValue"):
        if forbidden in loss:
            raise SystemExit(f"foreground loss introduced forbidden authority/claim: {forbidden}")

    if "foregroundIntegrityIsActive = true" not in active or "acceptsViewScopedMembershipRequests = true" not in active:
        raise SystemExit("active return must reopen only view-scoped request admission")
    for forbidden in (
        "sdkDeviceMembershipVerified = true",
        "membershipAccountUID =",
        "membershipDeviceID =",
        "beginCorrelationSeries",
        "beginOfficialConnection",
        "connectBLE",
        "currentConnectionToken =",
        "processCorrelationLease =",
    ):
        if forbidden in active:
            raise SystemExit(f"active return restored forbidden authority: {forbidden}")

    # Preserve exact newer truth while changing this lifecycle seam.
    for token in (
        "private var acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipAccountUID = nil",
        "membershipDeviceID = nil",
        "Task { @MainActor [self] in",
        "private static func redactApplicationSecrets(_ object: Any) -> Any",
        "guard !packageCorrelationRetiredForProcess,",
    ):
        if token not in source:
            raise SystemExit(f"newer flagship truth regressed: {token}")

    view_start = source.index("private struct SecureLinkView: View")
    view_end = source.index("private var hero: some View", view_start)
    view = source[view_start:view_end]
    for token in (
        "@Environment(\\.scenePhase) private var scenePhase",
        ".onChange(of: scenePhase)",
        "if newPhase == .active",
        "test.appDidBecomeActiveForView()",
        "test.appDidLoseForeground()",
        "if scenePhase == .active, sdkAccount.loggedIn { test.verifySDKMembership() }",
        ".onDisappear {\n            test.abandonCorrelationForViewExit()",
    ):
        if token not in view:
            raise SystemExit(f"Secure Link foreground view contract missing: {token}")

    if not TEST.exists():
        raise SystemExit("foreground source regression missing")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
