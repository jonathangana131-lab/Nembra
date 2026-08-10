#!/usr/bin/env python3
from pathlib import Path
import subprocess
import textwrap

EXPECTED_PARENT = "1c40853f6991b4d09206df1d25ecff021458b7eb"
ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureAppTruthConvergenceSourceTests.swift"
SCRIPT = ROOT / "scripts/ci/materialize_capture_app_truth_convergence_1c408.py"
WORKFLOW = ROOT / ".github/workflows/materialize-capture-app-truth-convergence-1c408.yml"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    return source.replace(old, new, 1)


if git("merge-base", "HEAD", EXPECTED_PARENT) != EXPECTED_PARENT:
    raise SystemExit("materializer is not descended from exact reviewed product parent")
helper_paths = set(git("diff", "--name-only", f"{EXPECTED_PARENT}...HEAD").splitlines())
allowed_helpers = {
    "scripts/ci/materialize_capture_app_truth_convergence_1c408.py",
    ".github/workflows/materialize-capture-app-truth-convergence-1c408.yml",
}
if not helper_paths or not helper_paths.issubset(allowed_helpers):
    raise SystemExit(f"unexpected pre-materialization paths: {sorted(helper_paths)}")

source = ENTRYPOINT.read_text()

source = replace_once(
    source,
    '''    func activateMembershipRequestsForView() {
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while the exact authenticated generation from foreground loss is still terminalizing.
        guard currentConnectionToken == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
    '''    func activateMembershipRequestsForView() {
        // Accepted artifacts are terminal. Do not reopen account authority just because the
        // app becomes active again after a completed, sealed capture.
        guard phase != .accepted else {
            acceptsViewScopedMembershipRequests = false
            return
        }
        // A fast inactive -> active transition must not reset the duplicate-retirement fence
        // while the exact authenticated generation from foreground loss is still terminalizing.
        guard currentConnectionToken == nil else { return }
        foregroundIntegrityLossHandled = false
        acceptsViewScopedMembershipRequests = true
    }
''',
    "accepted membership activation fence",
)

source = replace_once(
    source,
    '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
''',
    '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Secure Link ended. Exact scooter membership must be verified again for a new Capture session."
        membershipRequestID = UUID()
        membershipBusy = false
''',
    "view-exit membership-status revocation",
)

source = replace_once(
    source,
    '''    func appDidLoseForeground() {
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''',
    '''    func appDidLoseForeground() {
        // A sealed accepted artifact is immutable and shareable. Foreground transitions after
        // acceptance must not restart membership/network authority or mutate capture state.
        guard phase != .accepted else { return }
        guard !foregroundIntegrityLossHandled else { return }
        foregroundIntegrityLossHandled = true
''',
    "accepted foreground terminal fence",
)

# Only the foreground-loss block has this exact sequence now because view-exit received its
# status reset above. Keep the reset ahead of generation rotation.
source = replace_once(
    source,
    '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
''',
    '''        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Capture left the foreground. Exact scooter membership must be verified again before another attempt."
        membershipRequestID = UUID()
        membershipBusy = false
#if canImport(ThingSmartHomeKit)
        membershipProbe = nil
#endif
        officialConnectionRequestID = UUID()
''',
    "foreground membership-status revocation",
)

source = replace_once(
    source,
    '''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
''',
    '''        if processCorrelationLease != nil || correlationSession != nil {
            // Existing helper stops package transport before releasing this controller's lease.
            abandonPackageCorrelation()
            phase = .failed
            message = "Capture left the foreground during Bluetooth target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; interrupted windows are never reusable evidence."
            log("foreground_integrity_lost_during_target_correlation")
            return
        }

        if phase == .correlated || phase == .selected {
            // The four package windows may already be sealed and their live scanner/lease gone.
            // Foreground loss still invalidates that current-attempt correlation/selection proof.
            resetDiscoverySessionOnly()
            phase = .failed
            message = "Capture left the foreground after target correlation. Restart from OFF1 with a fresh OFF1→ON1→OFF2→ON2 series; pre-interruption target authority is never reused."
            log("foreground_integrity_lost_after_target_correlation")
            return
        }

        guard let token = currentConnectionToken else {
''',
    "sealed correlation foreground invalidation",
)

source = replace_once(
    source,
    '''    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        guard acceptsViewScopedMembershipRequests else {
''',
    '''    func verifySDKMembership(completion: ((Bool) -> Void)? = nil) {
        guard phase != .accepted else {
            completion?(false)
            return
        }
        guard acceptsViewScopedMembershipRequests else {
''',
    "accepted membership verification fence",
)

source = replace_once(
    source,
    '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
''',
    '''        guard let eventUpdate = applicationUpdateForEventCustody(update) else {
            await invalidateSourceAuthority(
                token: token,
                message: "Account identity lease became unavailable before application evidence could enter immutable event custody.",
                kind: "application_event_account_identity_unavailable"
            )
            return
        }

        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", eventUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
''',
    "application event custody and trusted generation precedence",
)

helper = '''
    private func applicationUpdateForEventCustody(_ update: [String: String]) -> [String: String]? {
        guard accountIdentityLeaseIsAuthorized,
              let leasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !leasedAccountUID.isEmpty else {
            return nil
        }

        let marker = "<redacted-account-uid>"
        var sanitized: [String: String] = [:]
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let baseKey = key.replacingOccurrences(of: leasedAccountUID, with: marker)
            var sanitizedKey = baseKey.isEmpty ? marker : baseKey
            var suffix = 2
            while sanitized[sanitizedKey] != nil {
                sanitizedKey = "\\(baseKey)#\\(suffix)"
                suffix += 1
            }
            sanitized[sanitizedKey] = value.replacingOccurrences(of: leasedAccountUID, with: marker)
        }
        return sanitized
    }

'''
source = replace_once(
    source,
    "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {\n",
    helper + "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {\n",
    "account UID event-custody helper",
)

source = replace_once(
    source,
    '''        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
''',
    '''        "accesstoken",
        "refreshtoken",
        "authkey",
''',
    "duplicate sessionkey simplification",
)

ENTRYPOINT.write_text(source)

TEST.write_text(textwrap.dedent('''
import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture current app truth convergence")
struct TuyaCaptureAppTruthConvergenceSourceTests {
    @Test("foreground loss revokes sealed correlation and never reopens accepted authority")
    func foregroundBoundaryClosesEveryMutableStage() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\\nprivate protocol OfficialTuyaDriver"
        ))
        let activation = String(try section(
            in: controller,
            from: "func activateMembershipRequestsForView()",
            to: "func abandonCorrelationForViewExit()"
        ))
        let cleanup = String(try section(
            in: controller,
            from: "func appDidLoseForeground()",
            to: "var privateConfig: Bool"
        ))

        #expect(activation.contains("guard phase != .accepted else"))
        #expect(cleanup.contains("guard phase != .accepted else { return }"))
        #expect(cleanup.contains("phase == .correlated || phase == .selected"))
        #expect(cleanup.contains("resetDiscoverySessionOnly()"))
        #expect(cleanup.contains("foreground_integrity_lost_after_target_correlation"))
        #expect(cleanup.contains("Task { @MainActor [self] in"))
        #expect(!cleanup.contains("recordObservedTransportLoss"))
        #expect(!cleanup.contains("endConnection("))
        #expect(!cleanup.contains("disconnectBLE"))
    }

    @Test("revoked membership proof cannot retain positive operator copy")
    func membershipStatusRevokesWithProof() throws {
        let source = try entrypointSource()
        let controller = String(try section(
            in: source,
            from: "private final class SecureLinkController",
            to: "@MainActor\\nprivate protocol OfficialTuyaDriver"
        ))
        for (start, end) in [
            ("func abandonCorrelationForViewExit()", "func appDidLoseForeground()"),
            ("func appDidLoseForeground()", "var privateConfig: Bool")
        ] {
            let cleanup = String(try section(in: controller, from: start, to: end))
            let clear = try requiredOffset(containing: "sdkDeviceMembershipVerified = false", in: cleanup)
            let status = try requiredOffset(containing: "membershipStatus =", in: cleanup)
            let rotate = try requiredOffset(containing: "membershipRequestID = UUID()", in: cleanup)
            #expect(clear < status)
            #expect(status < rotate)
            #expect(!cleanup.contains("membershipStatus = \\"Exact scooter membership verified and leased to this current SDK account.\\""))
        }
    }

    @Test("application event custody scrubs leased account UID and reserves Nembra generation")
    func applicationEventCustodyIsTrusted() throws {
        let source = try entrypointSource()
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("applicationUpdateForEventCustody(update)"))
        #expect(!receiver.contains("log(\\\"tuya_application_update\\\", update.merging(["))
        #expect(receiver.contains("\\\"generation\\\": String(token.diagnosticGeneration)"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("account UID scrub is value-bound and secret classifier has one session-key rule")
    func custodySimplificationPreservesGenericUIDEvidence() throws {
        let source = try entrypointSource()
        let driver = String(try section(
            in: source,
            from: "@MainActor\\nprivate final class SmartLifeDriver",
            to: "#endif\\n\\nprivate enum AppleAccountAuthorizationError"
        ))
        let classifier = String(try section(
            in: driver,
            from: "private static let secretKeyFragments = [",
            to: "]\\n\\n    private static func redactApplicationSecrets"
        ))

        #expect(!driver.contains("\\\"uid\\\","))
        #expect(classifier.components(separatedBy: "\\\"sessionkey\\\"").count - 1 == 1)
        #expect(source.contains("key.replacingOccurrences(of: leasedAccountUID"))
        #expect(source.contains("value.replacingOccurrences(of: leasedAccountUID"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \\(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func entrypointSource() throws -> String {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return try String(
            contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"),
            encoding: .utf8
        )
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
            throw ContractError.missing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private enum ContractError: Error { case missing }
}
''').lstrip())

final_source = ENTRYPOINT.read_text()
required = [
    "guard phase != .accepted else { return }",
    "phase == .correlated || phase == .selected",
    "foreground_integrity_lost_after_target_correlation",
    "Secure Link ended. Exact scooter membership must be verified again",
    "applicationUpdateForEventCustody(update)",
    "<redacted-account-uid>",
    ") { _, trusted in trusted })",
]
for token in required:
    if token not in final_source:
        raise SystemExit(f"missing required product token: {token}")
if final_source.count('"sessionkey",') != 1:
    raise SystemExit("sessionkey secret classifier must contain exactly one entry")
if ') { current, _ in current })' in final_source:
    raise SystemExit("untrusted application metadata still wins reserved generation")

SCRIPT.unlink()
WORKFLOW.unlink()
