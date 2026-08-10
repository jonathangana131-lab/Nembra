from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift"

PROPERTY_OLD = "    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n"
PROPERTY_NEW = "    private var acceptsViewScopedMembershipRequests = false\n    private var officialConnectionRequestID = UUID()\n    private var terminalRetirementToken: TuyaReadOnlyConnectionToken?\n"

ACTIVATE_OLD = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }
'''
ACTIVATE_NEW = '''    func activateMembershipRequestsForView() {
        acceptsViewScopedMembershipRequests = true
    }
'''

EXIT_TOKEN_OLD = '''        if let token = currentConnectionToken {
            phase = .failed
            message = "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("authenticated_session_abandoned_on_view_exit", ["generation": String(token.diagnosticGeneration)])
            Task { @MainActor [self] in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "authenticated_session_abandoned_on_view_exit"
                )
            }
            return
        }
'''
EXIT_TOKEN_NEW = '''        if let token = currentConnectionToken {
            guard terminalRetirementToken != token else {
                log("view_exit_terminal_retirement_already_in_flight", ["generation": String(token.diagnosticGeneration)])
                return
            }
            terminalRetirementToken = token
            phase = .failed
            message = "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed."
            log("authenticated_session_abandoned_on_view_exit", ["generation": String(token.diagnosticGeneration)])
            Task { @MainActor [self] in
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "Authenticated observation stopped because Capture left Secure Link. Relaunch before another authenticated attempt; no BLE disconnect is claimed.",
                    kind: "authenticated_session_abandoned_on_view_exit"
                )
                if self.terminalRetirementToken == token {
                    self.terminalRetirementToken = nil
                }
            }
            return
        }
'''

FOREGROUND_METHOD = '''
    func appDidLoseForeground() {
        // Capture evidence and authority acquisition are foreground-only. Close admission before
        // revoking already-issued async grants so a queued account callback cannot mint a fresh
        // membership probe after the scene becomes inactive.
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
            message = "Capture left the foreground during Bluetooth target correlation. After Capture is active again, restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series. Interrupted windows are not reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            if phase == .authenticating {
                localBLESettlementToken = nil
                sdkLocalBLEOnline = false
                driver = nil
                phase = .failed
                message = "Capture left the foreground during authentication. Relaunch before another authenticated stationary attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        guard terminalRetirementToken != token else {
            log("foreground_terminal_retirement_already_in_flight", ["generation": String(token.diagnosticGeneration)])
            return
        }
        terminalRetirementToken = token
        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another authenticated stationary attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // Strongly retain this finite terminal operation. Scene/view teardown must not make exact
        // package-generation retirement best-effort.
        Task { @MainActor [self] in
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch before a new stationary read-only attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another authenticated stationary attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
            if self.terminalRetirementToken == token {
                self.terminalRetirementToken = nil
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

TASK_OLD = '''        .task {
            test.activateMembershipRequestsForView()
            sdkAccount.bootstrap()
            if sdkAccount.loggedIn { test.verifySDKMembership() }
            while !Task.isCancelled {
'''
TASK_NEW = '''        .task {
            if scenePhase == .active {
                test.activateMembershipRequestsForView()
            }
            sdkAccount.bootstrap()
            if scenePhase == .active, sdkAccount.loggedIn {
                test.verifySDKMembership()
            }
            while !Task.isCancelled {
'''

DISAPPEAR_OLD = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''
DISAPPEAR_NEW = '''        .onDisappear {
            test.abandonCorrelationForViewExit()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Re-open only request admission. Recovery remains explicit; returning to the
                // foreground does not restart correlation or authenticate automatically.
                test.activateMembershipRequestsForView()
            } else {
                test.appDidLoseForeground()
            }
        }
        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link owns an explicit active-scene evidence boundary")
    func secureLinkOwnsForegroundIntegrity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let view = String(try section(in: source, from: "private struct SecureLinkView: View", to: "private var hero: some View"))

        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains("if scenePhase == .active"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase == .active"))
        #expect(view.contains("test.activateMembershipRequestsForView()"))
        #expect(view.contains("test.appDidLoseForeground()"))
    }

    @Test("foreground loss closes membership admission before revoking grants or transport")
    func foregroundLossOrdersAuthorityRevocation() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let revokeProof = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let revokeMembership = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let revokeOfficial = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let cancelWatchdog = try requiredOffset(containing: "watchdog?.cancel()", in: cleanup)
        let correlationCheck = try requiredOffset(containing: "if processCorrelationLease != nil || correlationSession != nil", in: cleanup)

        #expect(closeAdmission < revokeProof)
        #expect(revokeProof < revokeMembership)
        #expect(revokeMembership < revokeOfficial)
        #expect(revokeOfficial < cancelWatchdog)
        #expect(cancelWatchdog < correlationCheck)
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))
    }

    @Test("foreground and navigation terminals cannot race the same ledger token")
    func exactTokenHasOneViewLifecycleTerminalOwner() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let navigation = String(try section(in: controller, from: "func abandonCorrelationForViewExit()", to: "func appDidLoseForeground()"))
        let foreground = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(controller.contains("private var terminalRetirementToken: TuyaReadOnlyConnectionToken?"))
        #expect(navigation.contains("guard terminalRetirementToken != token else"))
        #expect(navigation.contains("terminalRetirementToken = token"))
        #expect(navigation.contains("Task { @MainActor [self] in"))
        #expect(foreground.contains("guard terminalRetirementToken != token else"))
        #expect(foreground.contains("terminalRetirementToken = token"))
        #expect(foreground.contains("Task { @MainActor [self] in"))
        #expect(foreground.contains("self.terminalRetirementToken = nil"))
    }

    @Test("foreground terminal distinguishes observation continuity from authentication lifecycle")
    func foregroundTerminalUsesTruthfulPackageTerminal() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(in: source, from: "private final class SecureLinkController", to: "@MainActor\nprivate protocol OfficialTuyaDriver"))
        let cleanup = String(try section(in: controller, from: "func appDidLoseForeground()", to: "var privateConfig: Bool"))

        #expect(cleanup.contains("let wasObserving = phase == .observing"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("Relaunch before a new stationary read-only attempt"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains("disconnectBLE"))
        #expect(!cleanup.contains("publishDps"))
        #expect(!cleanup.contains("queryDps"))
        #expect(!cleanup.contains("writeValue"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def require_count(source: str, token: str, expected: int, label: str) -> None:
    actual = source.count(token)
    if actual != expected:
        raise SystemExit(f"{label}: expected {expected} match(es), found {actual}")


def apply() -> None:
    app = APP.read_text(encoding="utf-8")
    require_count(app, PROPERTY_OLD, 1, "current lifecycle properties")
    require_count(app, ACTIVATE_OLD, 1, "membership activation")
    require_count(app, EXIT_TOKEN_OLD, 1, "strong navigation terminal")
    require_count(app, ENV_OLD, 1, "Secure Link environment")
    require_count(app, TASK_OLD, 1, "Secure Link task")
    require_count(app, DISAPPEAR_OLD, 1, "Secure Link lifecycle modifiers")
    require_count(app, '"accounttoken"', 1, "current expanded application secret contract")

    app = app.replace(PROPERTY_OLD, PROPERTY_NEW, 1)
    app = app.replace(EXIT_TOKEN_OLD, EXIT_TOKEN_NEW, 1)
    app = app.replace(ACTIVATE_OLD, ACTIVATE_NEW + FOREGROUND_METHOD, 1)
    app = app.replace(ENV_OLD, ENV_NEW, 1)
    app = app.replace(TASK_OLD, TASK_NEW, 1)
    app = app.replace(DISAPPEAR_OLD, DISAPPEAR_NEW, 1)
    APP.write_text(app, encoding="utf-8")

    if TEST.exists():
        raise SystemExit("foreground integrity source regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    app = APP.read_text(encoding="utf-8")
    for token in (
        "@Environment(\\.scenePhase) private var scenePhase",
        "func appDidLoseForeground()",
        "private var terminalRetirementToken: TuyaReadOnlyConnectionToken?",
        "acceptsViewScopedMembershipRequests = false",
        "invalidateObservationContinuity(",
        "Task { @MainActor [self] in",
        '"accounttoken"',
    ):
        if token not in app:
            raise SystemExit(f"required current foreground/product token missing: {token}")
    if not TEST.exists():
        raise SystemExit("foreground integrity source regression missing")
    test = TEST.read_text(encoding="utf-8")
    for token in (
        "foregroundLossOrdersAuthorityRevocation",
        "exactTokenHasOneViewLifecycleTerminalOwner",
        "foregroundTerminalUsesTruthfulPackageTerminal",
    ):
        if token not in test:
            raise SystemExit(f"foreground regression missing: {token}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
