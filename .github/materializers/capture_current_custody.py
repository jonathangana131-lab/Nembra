#!/usr/bin/env python3
from pathlib import Path
import subprocess

BASE = "1c40853f6991b4d09206df1d25ecff021458b7eb"
WORKFLOW = ".github/workflows/capture-current-custody-materializer.yml"
SCRIPT = ".github/materializers/capture_current_custody.py"
SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TESTS = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def bounds(text: str, start: str, end: str) -> tuple[int, int]:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"missing start marker: {start}")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"missing end marker: {end}")
    return a, b


def replace_once_in(text: str, start: str, end: str, old: str, new: str) -> str:
    a, b = bounds(text, start, end)
    section = text[a:b]
    count = section.count(old)
    if count != 1:
        raise SystemExit(f"expected one match in {start!r}, got {count}: {old!r}")
    return text[:a] + section.replace(old, new, 1) + text[b:]


changed_before = set(run("git", "diff", "--name-only", BASE, "HEAD").splitlines())
expected_setup = {WORKFLOW, SCRIPT}
if changed_before != expected_setup:
    raise SystemExit(f"unexpected setup delta: {sorted(changed_before)}")

source = SOURCE.read_text()
authority_clear = """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
"""
source = replace_once_in(
    source,
    "    func abandonCorrelationForViewExit() {",
    "    func appDidLoseForeground() {",
    authority_clear,
    """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Secure Link left this view. Exact scooter membership must be verified again before Bluetooth discovery."
        membershipRequestID = UUID()
""",
)
source = replace_once_in(
    source,
    "    func appDidLoseForeground() {",
    "    var privateConfig: Bool",
    authority_clear,
    """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = "Capture left the foreground. Exact scooter membership must be verified again before Bluetooth discovery."
        membershipRequestID = UUID()
""",
)

guard_old = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
"""
guard_new = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device source authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
            )
            return
        }
        guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity disappeared before application evidence custody.",
                kind: "sdk_account_uid_authority_missing_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
"""
source = replace_once_in(
    source,
    "    private func receivedApplicationUpdate(",
    "    private func startWatchdog",
    guard_old,
    guard_new,
)

log_old = """            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
"""
log_new = """            let eventUpdate = scrubAccountUIDFromApplicationEvent(
                update,
                verifiedAccountUID: verifiedAccountUID
            )
            log("tuya_application_update", eventUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
"""
source = replace_once_in(
    source,
    "    private func receivedApplicationUpdate(",
    "    private func startWatchdog",
    log_old,
    log_new,
)

helper = """    private func scrubAccountUIDFromApplicationEvent(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let marker = "<redacted-account-uid>"
        var sanitized: [String: String] = [:]
        sanitized.reserveCapacity(update.count)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(of: verifiedAccountUID, with: marker)
            let redactedValue = value.replacingOccurrences(of: verifiedAccountUID, with: marker)
            sanitized[redactedKey] = redactedValue
        }
        return sanitized
    }

"""
watchdog = "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
if source.count(watchdog) != 1:
    raise SystemExit("startWatchdog marker not unique")
source = source.replace(watchdog, helper + watchdog, 1)

duplicate = """        "refreshtoken",
        "sessionkey",
        "authkey",
"""
if source.count(duplicate) != 1:
    raise SystemExit("duplicate sessionkey sequence changed unexpectedly")
source = source.replace(duplicate, """        "refreshtoken",
        "authkey",
""", 1)
SOURCE.write_text(source)

membership_test = '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Secure Link membership status revocation")
struct TuyaSecureLinkViewMembershipStatusRevocationSourceTests {
    @Test("view exit revokes status with membership proof")
    func viewExitRevokesStatus() throws {
        let source = try repositorySource()
        let cleanup = String(try section(source, "func abandonCorrelationForViewExit()", "func appDidLoseForeground()"))
        try assertOrdering(cleanup)
        #expect(cleanup.contains("membershipStatus = \\"Secure Link left this view."))
    }

    @Test("foreground loss revokes status with membership proof")
    func foregroundLossRevokesStatus() throws {
        let source = try repositorySource()
        let cleanup = String(try section(source, "func appDidLoseForeground()", "var privateConfig: Bool"))
        try assertOrdering(cleanup)
        #expect(cleanup.contains("membershipStatus = \\"Capture left the foreground."))
    }

    private func assertOrdering(_ text: String) throws {
        let clear = try offset("sdkDeviceMembershipVerified = false", text)
        let status = try offset("membershipStatus =", text)
        let revoke = try offset("membershipRequestID = UUID()", text)
        #expect(clear < status)
        #expect(status < revoke)
        #expect(!text.contains("membershipStatus = \\"Exact scooter membership verified and leased to this current SDK account.\\""))
    }

    private func offset(_ token: String, _ text: String) throws -> String.Index {
        guard let range = text.range(of: token) else { throw SourceError.missing }
        return range.lowerBound
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
'''

precedence_test = '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWins() throws {
        let source = try repositorySource()
        let receiver = String(try section(source, "private func receivedApplicationUpdate(", "private func startWatchdog"))
        #expect(receiver.contains("log(\\"tuya_application_update\\""))
        #expect(receiver.contains("\\"generation\\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
'''

uid_test = '''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence scrubs exact verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try repositorySource()
        let admission = String(try section(source, "private func receivedApplicationUpdate(", "private func startWatchdog"))
        let export = String(try section(source, "func prepareExport()", "private func abandonPackageCorrelation()"))
        #expect(export.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(admission.contains("verifiedAccountUID"))
        #expect(admission.contains("scrubAccountUIDFromApplicationEvent"))
        #expect(!admission.contains("log(\\"tuya_application_update\\", update.merging(["))
    }

    @Test("UID scrub is exact-value-bound rather than a generic uid-key rule")
    func valueBoundScrub() throws {
        let source = try repositorySource()
        let helper = String(try section(source, "private func scrubAccountUIDFromApplicationEvent(", "private func startWatchdog"))
        let driver = String(try section(source, "@MainActor\\nprivate final class SmartLifeDriver", "#endif\\n\\nprivate enum AppleAccountAuthorizationError"))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(!driver.contains("\\"uid\\","))
        #expect(!driver.contains("\\"uid\\"\\n"))
    }

    private func section(_ text: String, _ start: String, _ end: String) throws -> Substring {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { throw SourceError.missing }
        return text[a.lowerBound..<b.lowerBound]
    }

    private func repositorySource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("NembraApp/App/NembraCaptureEntrypoint.swift"), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
'''

new_tests = {
    TESTS / "TuyaSecureLinkViewMembershipStatusRevocationSourceTests.swift": membership_test,
    TESTS / "TuyaApplicationEventMetadataPrecedenceSourceTests.swift": precedence_test,
    TESTS / "TuyaApplicationAccountUIDExportCustodySourceTests.swift": uid_test,
}
for path, content in new_tests.items():
    if path.exists():
        raise SystemExit(f"refusing to overwrite existing test: {path}")
    path.write_text(content)

subprocess.run(["git", "diff", "--check"], check=True)
source = SOURCE.read_text()
assert source.count('"sessionkey",') == 1
assert '<redacted-account-uid>' in source
assert ']) { _, trusted in trusted })' in source
assert 'log("tuya_application_update", update.merging([' not in source
assert 'membershipStatus = "Secure Link left this view.' in source
assert 'membershipStatus = "Capture left the foreground.' in source

Path(WORKFLOW).unlink()
Path(SCRIPT).unlink()
subprocess.run(["git", "diff", "--check"], check=True)
subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
subprocess.run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): close current membership and export custody"], check=True)
subprocess.run(["git", "push", "origin", "HEAD:repair/v14-capture-current-custody-sol"], check=True)
