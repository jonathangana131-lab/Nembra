from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegrityCurrentSourceTests.swift"

CONTROLLER_ANCHOR = "    var privateConfig: Bool { OfficialTuyaFactory.configured }\n"
VIEW_ENV_ANCHOR = "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n"
VIEW_LIFECYCLE_ANCHOR = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''

FOREGROUND_METHOD = '''    func appDidLoseForeground() {
        // A sealed accepted artifact is immutable presentation/share authority. Do not mutate its
        // accepted state merely because the app later becomes inactive.
        guard phase != .accepted else { return }

        // Foreground-only Capture evidence must revoke view/account authority before inspecting
        // any transport state. Late membership/auth callbacks cannot start hidden radio work.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Capture left the foreground. Exact scooter membership must be verified again before another attempt."
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
        watchdog?.cancel()
        watchdog = nil

        if processCorrelationLease != nil || correlationSession != nil {
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        if phase == .correlated || phase == .selected {
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after target correlation. Restart from OFF1; correlated target authority cannot cross a foreground interruption."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        if let token = currentConnectionToken {
            let wasObserving = phase == .observing
            phase = .failed
            message = wasObserving
                ? "Capture left the foreground during authenticated observation. Restart from OFF1; background time is not accepted evidence and no BLE disconnect is claimed."
                : "Capture left the foreground before authenticated observation. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log(
                wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
                ["generation": String(token.diagnosticGeneration)]
            )
            Task { @MainActor [self] in
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
            return
        }

        if phase == .authenticating {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            phase = .failed
            message = "Capture left the foreground during authentication. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("foreground_integrity_lost_before_observation")
        }
    }

'''

SCENE_ENV = "    @Environment(\\.scenePhase) private var scenePhase\n"
SCENE_LIFECYCLE = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                test.activateMembershipRequestsForView()
                if sdkAccount.loggedIn { test.verifySDKMembership() }
            } else {
                test.appDidLoseForeground()
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current foreground integrity")
struct TuyaCaptureForegroundIntegrityCurrentSourceTests {
    @Test("Secure Link owns scene-phase loss and fresh foreground return authority")
    func secureLinkOwnsForegroundLoss() throws {
        let source = try entrypointSource()
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("if sdkAccount.loggedIn { test.verifySDKMembership() }"))
        #expect(view.contains("test.appDidLoseForeground()"))
        #expect(controller.contains("func appDidLoseForeground()"))
    }

    @Test("foreground loss preserves sealed acceptance but revokes mutable authority before transport inspection")
    func foregroundLossRevokesMutableAuthority() throws {
        let source = try entrypointSource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        let membershipAdmissionClose = try requiredOffset("acceptsViewScopedMembershipRequests = false", in: cleanup)
        let proofClear = try requiredOffset("sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset("membershipStatus =", in: cleanup)
        let membershipRevoke = try requiredOffset("membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset("officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset("if processCorrelationLease != nil || correlationSession != nil", in: cleanup)
        #expect(membershipAdmissionClose < correlationCheck)
        #expect(proofClear < correlationCheck)
        #expect(statusReset < correlationCheck)
        #expect(membershipRevoke < correlationCheck)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipAccountUID = nil"))
        #expect(cleanup.contains("membershipDeviceID = nil"))
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("already correlated target authority cannot cross foreground boundary")
    func correlatedTargetCannotCrossForegroundBoundary() throws {
        let source = try entrypointSource()
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
    }

    private func requiredOffset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw ContractError.missing }
        return range.lowerBound
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw ContractError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
'''


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if FOREGROUND_METHOD.strip() in source or "func appDidLoseForeground()" in source:
        raise SystemExit("foreground-integrity method already exists; re-inspect current product")
    if source.count(CONTROLLER_ANCHOR) != 1 or source.count(VIEW_ENV_ANCHOR) != 1 or source.count(VIEW_LIFECYCLE_ANCHOR) != 1:
        raise SystemExit("foreground-integrity source anchors changed")
    source = source.replace(CONTROLLER_ANCHOR, FOREGROUND_METHOD + CONTROLLER_ANCHOR, 1)
    source = source.replace(VIEW_ENV_ANCHOR, VIEW_ENV_ANCHOR + SCENE_ENV, 1)
    source = source.replace(VIEW_LIFECYCLE_ANCHOR, SCENE_LIFECYCLE, 1)
    ENTRYPOINT.write_text(source, encoding="utf-8")
    if TEST.exists():
        raise SystemExit("current foreground-integrity regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if source.count("func appDidLoseForeground()") != 1:
        raise SystemExit("foreground-integrity method is not exact and unique")
    for token in (
        "guard phase != .accepted else { return }",
        "acceptsViewScopedMembershipRequests = false",
        "sdkDeviceMembershipVerified = false",
        "membershipStatus = \"Capture left the foreground.",
        "officialConnectionRequestID = UUID()",
        "phase == .correlated || phase == .selected",
        "resetDiscoverySessionOnly()",
        "invalidateObservationContinuity(",
        "invalidateInternalLifecycle(",
        "Task { @MainActor [self] in",
        "@Environment(\\.scenePhase) private var scenePhase",
        ".onChange(of: scenePhase)",
        "if newPhase == .active",
    ):
        if token not in source:
            raise SystemExit(f"foreground-integrity token missing: {token}")
    if not TEST.exists():
        raise SystemExit("foreground-integrity regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
