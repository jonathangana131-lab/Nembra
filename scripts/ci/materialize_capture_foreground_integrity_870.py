#!/usr/bin/env python3
from pathlib import Path
import subprocess
import textwrap

EXPECTED_PARENT = "870f20abe144fa7b6f9ac60bf4c0fe0a1792fb81"
ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
FOREGROUND_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureForegroundIntegritySourceTests.swift"
STATUS_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift"
SCRIPT = ROOT / "scripts/ci/materialize_capture_foreground_integrity_870.py"
WORKFLOW = ROOT / ".github/workflows/materialize-capture-foreground-integrity-870.yml"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


if git("merge-base", "HEAD", EXPECTED_PARENT) != EXPECTED_PARENT:
    raise SystemExit("materializer is not descended from the exact reviewed product parent")

helper_paths = set(git("diff", "--name-only", f"{EXPECTED_PARENT}...HEAD").splitlines())
allowed_helpers = {
    "scripts/ci/materialize_capture_foreground_integrity_870.py",
    ".github/workflows/materialize-capture-foreground-integrity-870.yml",
}
if not helper_paths or not helper_paths.issubset(allowed_helpers):
    raise SystemExit(f"unexpected pre-materialization paths: {sorted(helper_paths)}")

source = ENTRYPOINT.read_text()
if "func appDidLoseForeground()" in source or "@Environment(\\.scenePhase) private var scenePhase" in source:
    raise SystemExit("foreground-integrity product repair already exists; refusing duplicate materialization")
if "private var foregroundIntegrityLost = false" in source:
    raise SystemExit("foreground one-shot fence already exists; refusing duplicate materialization")

source = replace_once(
    source,
    "    private var officialConnectionRequestID = UUID()\n",
    "    private var officialConnectionRequestID = UUID()\n    private var foregroundIntegrityLost = false\n",
    "foreground one-shot storage",
)
source = replace_once(
    source,
    "    func activateMembershipRequestsForView() {\n        acceptsViewScopedMembershipRequests = true\n    }\n",
    "    func activateMembershipRequestsForView() {\n        guard !foregroundIntegrityLost else { return }\n        acceptsViewScopedMembershipRequests = true\n    }\n",
    "view-scoped membership admission",
)
source = replace_once(
    source,
    "        sdkDeviceMembershipVerified = false\n        membershipAccountUID = nil\n        membershipDeviceID = nil\n        membershipRequestID = UUID()\n",
    "        sdkDeviceMembershipVerified = false\n        membershipAccountUID = nil\n        membershipDeviceID = nil\n        membershipStatus = \"Secure Link ended. Exact scooter membership must be verified again for a new Capture session.\"\n        membershipRequestID = UUID()\n",
    "view-exit membership status revocation",
)

foreground_method = r'''
    func appDidLoseForeground() {
        // A single inactive/background transition invalidates this Secure Link controller for
        // physical-evidence purposes. Scene phase may advance inactive -> background, so admit
        // the terminal transition exactly once and never reopen it inside this controller.
        guard !foregroundIntegrityLost else { return }
        foregroundIntegrityLost = true

        // Close every view/account admission before rotating issued async generations. A later
        // SwiftUI/account callback must not mint new membership work while the app is inactive.
        acceptsViewScopedMembershipRequests = false
        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Capture left the foreground. Exact scooter membership must be verified again after relaunch."
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
            message = "Capture left the foreground during Bluetooth target correlation. Relaunch before a fresh stationary OFF1 attempt; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
            localBLESettlementToken = nil
            sdkLocalBLEOnline = false
            driver = nil
            if phase != .failed && phase != .accepted {
                phase = .failed
                message = "Capture left the foreground before authenticated observation completed. Relaunch before another stationary authenticated attempt; no BLE disconnect is claimed."
                log("foreground_integrity_lost_before_observation")
            }
            return
        }

        let wasObserving = phase == .observing
        phase = .failed
        message = wasObserving
            ? "Capture left the foreground during authenticated observation. Relaunch before another stationary attempt; background time is not accepted evidence and no BLE disconnect is claimed."
            : "Capture left the foreground before authenticated observation. Relaunch before another stationary authenticated attempt; no BLE disconnect is claimed."
        log(
            wasObserving ? "foreground_integrity_lost_during_observation" : "foreground_integrity_lost_before_observation",
            ["generation": String(token.diagnosticGeneration)]
        )

        // Strongly retain the controller only for this finite exact-generation retirement. This
        // mirrors the accepted view-exit lifetime rule: deallocation must not skip the terminal.
        Task { @MainActor [self] in
            guard self.currentConnectionToken == token else { return }
            if wasObserving {
                await self.invalidateObservationContinuity(
                    token: token,
                    message: "App foreground integrity was lost during authenticated observation. Relaunch before another stationary attempt; background time is not accepted evidence and no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_during_observation"
                )
            } else {
                await self.invalidateInternalLifecycle(
                    token: token,
                    message: "App foreground integrity was lost before authenticated observation. Relaunch before another stationary authenticated attempt; no BLE disconnect is claimed.",
                    kind: "foreground_integrity_lost_before_observation"
                )
            }
        }
    }
'''
source = replace_once(
    source,
    "\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n",
    foreground_method + "\n    var privateConfig: Bool { OfficialTuyaFactory.configured }\n",
    "foreground method insertion",
)
source = replace_once(
    source,
    "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n",
    "    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize\n    @Environment(\\.scenePhase) private var scenePhase\n",
    "scene-phase environment",
)
source = replace_once(
    source,
    "        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n",
    "        .onDisappear {\n            test.abandonCorrelationForViewExit()\n        }\n        .onChange(of: scenePhase) { _, newPhase in\n            if newPhase != .active {\n                test.appDidLoseForeground()\n            }\n        }\n        .onChange(of: sdkAccount.loggedIn) { _, loggedIn in\n",
    "scene-phase observer",
)
ENTRYPOINT.write_text(source)

FOREGROUND_TEST.write_text(textwrap.dedent(r'''\
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture foreground integrity source contract")
struct TuyaCaptureForegroundIntegritySourceTests {
    @Test("Secure Link closes foreground evidence authority exactly once")
    func secureLinkOwnsForegroundIntegrity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let view = String(try section(
            in: source,
            from: "private struct SecureLinkView: View",
            to: "private var hero: some View"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))

        #expect(controller.contains("private var foregroundIntegrityLost = false"))
        #expect(activation.contains("guard !foregroundIntegrityLost else { return }"))
        #expect(view.contains("@Environment(\\.scenePhase) private var scenePhase"))
        #expect(view.contains(".onChange(of: scenePhase)"))
        #expect(view.contains("if newPhase != .active"))
        #expect(view.contains("test.appDidLoseForeground()"))

        let oneShot = try requiredOffset(containing: "guard !foregroundIntegrityLost else { return }", in: cleanup)
        let closeAdmission = try requiredOffset(containing: "acceptsViewScopedMembershipRequests = false", in: cleanup)
        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let clearAccountLease = try requiredOffset(containing: "membershipAccountUID = nil", in: cleanup)
        let clearDeviceLease = try requiredOffset(containing: "membershipDeviceID = nil", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let membershipRevoke = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
        let officialRevoke = try requiredOffset(containing: "officialConnectionRequestID = UUID()", in: cleanup)
        let correlationCheck = try requiredOffset(
            containing: "if processCorrelationLease != nil || correlationSession != nil",
            in: cleanup
        )
        #expect(oneShot < closeAdmission)
        #expect(closeAdmission < clearVerified)
        #expect(clearVerified < membershipRevoke)
        #expect(clearAccountLease < membershipRevoke)
        #expect(clearDeviceLease < membershipRevoke)
        #expect(statusReset < membershipRevoke)
        #expect(membershipRevoke < officialRevoke)
        #expect(officialRevoke < correlationCheck)
        #expect(cleanup.contains("membershipBusy = false"))
        #expect(cleanup.contains("membershipProbe = nil"))
        #expect(cleanup.contains("watchdog?.cancel()"))

        #expect(cleanup.contains("abandonPackageCorrelation()"))
        #expect(cleanup.contains("foreground_integrity_lost_during_target_correlation"))
        #expect(!cleanup.contains("releasePackageCorrelationLease()"))

        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("Task { @MainActor [weak self]"))
        #expect(cleanup.contains("invalidateObservationContinuity("))
        #expect(cleanup.contains("foreground_integrity_lost_during_observation"))
        #expect(cleanup.contains("invalidateInternalLifecycle("))
        #expect(cleanup.contains("foreground_integrity_lost_before_observation"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection"))
        #expect(!cleanup.contains(".disconnect("))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
'''))

STATUS_TEST.write_text(textwrap.dedent(r'''\
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link view-exit membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit cannot retain verified membership copy after revoking the membership proof")
    func exitRevokesMembershipStatusWithProof() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\nprivate protocol OfficialTuyaDriver"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func abandonCorrelationForViewExit()",
            to: "func appDidLoseForeground()"
        ))

        let clearVerified = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
        let statusReset = try requiredOffset(containing: "membershipStatus =", in: cleanup)
        let revokeMembershipRequest = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)

        #expect(clearVerified < statusReset)
        #expect(statusReset < revokeMembershipRequest)
        #expect(cleanup.lowercased().contains("verif"))
        #expect(!cleanup.contains("membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\""))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
'''))

# Product-tree invariants before the helper deletes itself.
final_source = ENTRYPOINT.read_text()
required = [
    "private var foregroundIntegrityLost = false",
    "guard !foregroundIntegrityLost else { return }",
    "func appDidLoseForeground()",
    "acceptsViewScopedMembershipRequests = false",
    "Task { @MainActor [self] in",
    "@Environment(\\.scenePhase) private var scenePhase",
    ".onChange(of: scenePhase)",
    "Secure Link ended. Exact scooter membership must be verified again",
]
for token in required:
    if token not in final_source:
        raise SystemExit(f"missing required product token after materialization: {token}")

for forbidden in [
    "func appDidLoseForeground() {\n        membershipRequestID = UUID()",
    "Task { @MainActor [weak self] in\n            guard let self, self.currentConnectionToken == token",
]:
    if forbidden in final_source:
        raise SystemExit(f"forbidden stale foreground pattern survived: {forbidden}")

SCRIPT.unlink()
WORKFLOW.unlink()
