#!/usr/bin/env python3
from pathlib import Path
import subprocess

BASE = "8069c0ffec496cacbe263016d8a7f4ca15ddc64e"
WORKFLOW = ".github/workflows/capture-event-custody-8069-materializer.yml"
SCRIPT = ".github/materializers/capture_event_custody_8069.py"
SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TESTS = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests")


def out(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def section_bounds(text: str, start: str, end: str) -> tuple[int, int]:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"missing section start: {start}")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"missing section end: {end}")
    return a, b


def replace_once_in(text: str, start: str, end: str, old: str, new: str) -> str:
    a, b = section_bounds(text, start, end)
    section = text[a:b]
    if section.count(old) != 1:
        raise SystemExit(f"unexpected match count for {old!r} in {start!r}: {section.count(old)}")
    return text[:a] + section.replace(old, new, 1) + text[b:]


setup_delta = set(out("git", "diff", "--name-only", BASE, "HEAD").splitlines())
if setup_delta != {WORKFLOW, SCRIPT}:
    raise SystemExit(f"unexpected setup delta: {sorted(setup_delta)}")

source = SOURCE.read_text()

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
              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty,
              let driver else {
            await invalidateSourceAuthority(
                token: token,
                message: "SDK account/device identity authority changed before application evidence arrived.",
                kind: "sdk_source_authority_changed_during_observation"
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

watchdog_marker = "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
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
if source.count(watchdog_marker) != 1:
    raise SystemExit("startWatchdog marker changed unexpectedly")
source = source.replace(watchdog_marker, helper + watchdog_marker, 1)

duplicate_session_key = """        "refreshtoken",
        "sessionkey",
        "authkey",
"""
if source.count(duplicate_session_key) != 1:
    raise SystemExit("duplicate sessionkey classifier sequence changed unexpectedly")
source = source.replace(
    duplicate_session_key,
    """        "refreshtoken",
        "authkey",
""",
    1,
)
SOURCE.write_text(source)

precedence_test = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("log(\"tuya_application_update\""))
        #expect(receiver.contains("\"generation\": String(token.diagnosticGeneration)"))
        #expect(!receiver.contains(") { current, _ in current })"))
        #expect(receiver.contains(") { _, trusted in trusted })"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
'''

uid_test = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence scrubs verified account UID before immutable event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let export = String(try section(in: source, from: "func prepareExport()", to: "private func abandonPackageCorrelation()"))
        #expect(export.contains("No account UID"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID?"))
        #expect(receiver.contains("scrubAccountUIDFromApplicationEvent"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("scrub is exact account-value bound and covers malformed UID-bearing keys without a blanket uid classifier")
    func valueBoundCustodyPreservesGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private func scrubAccountUIDFromApplicationEvent(", to: "private func startWatchdog"))
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(helper.contains("key.replacingOccurrences(of: verifiedAccountUID"))
        #expect(helper.contains("value.replacingOccurrences(of: verifiedAccountUID"))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    @Test("secret classifier keeps one session-key rule after custody convergence")
    func secretClassifierIsSimplified() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(driver.components(separatedBy: "\"sessionkey\",").count - 1 == 1)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceError.missing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceError: Error { case missing }
}
'''

new_tests = {
    TESTS / "TuyaApplicationEventMetadataPrecedenceSourceTests.swift": precedence_test,
    TESTS / "TuyaApplicationAccountUIDExportCustodySourceTests.swift": uid_test,
}
for path, content in new_tests.items():
    if path.exists():
        raise SystemExit(f"refusing to overwrite existing path: {path}")
    path.write_text(content)

subprocess.run(["git", "diff", "--check"], check=True)
materialized = SOURCE.read_text()
assert materialized.count('"sessionkey",') == 1
assert '<redacted-account-uid>' in materialized
assert ']) { _, trusted in trusted })' in materialized
assert 'log("tuya_application_update", update.merging([' not in materialized

Path(WORKFLOW).unlink()
Path(SCRIPT).unlink()
subprocess.run(["git", "diff", "--check"], check=True)
subprocess.run(["git", "config", "user.name", "github-actions[bot]"], check=True)
subprocess.run(["git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], check=True)
subprocess.run(["git", "add", "-A"], check=True)
subprocess.run(["git", "commit", "-m", "fix(capture): bind application event custody to trusted authority"], check=True)
subprocess.run(["git", "push", "origin", "HEAD:repair/v14-capture-event-custody-8069-sol"], check=True)
