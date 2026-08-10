#!/usr/bin/env python3
from pathlib import Path
import subprocess

EXPECTED_PARENT = "ba3a1eeae36caca6dd84beaabd0f15f4f0b57925"
ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift"
SCRIPT = ROOT / "scripts/ci/materialize_capture_event_custody_lease_race_ba3a.py"
WORKFLOW = ROOT / ".github/workflows/materialize-capture-event-custody-lease-race-ba3a.yml"


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
    "scripts/ci/materialize_capture_event_custody_lease_race_ba3a.py",
    ".github/workflows/materialize-capture-event-custody-lease-race-ba3a.yml",
}
if not helper_paths or not helper_paths.issubset(allowed_helpers):
    raise SystemExit(f"unexpected pre-materialization paths: {sorted(helper_paths)}")

source = ENTRYPOINT.read_text()

source = replace_once(
    source,
    '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
''',
    '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }
        guard let leasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !leasedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "The exact account identity lease was unavailable before application evidence entered event custody.",
                kind: "application_event_account_identity_unavailable"
            )
            return
        }
        // Freeze the privacy projection before the first suspension point. Foreground/account
        // revocation may clear the live lease while package chronology is awaiting actor work;
        // that must never turn an already-admitted SDK dictionary back into raw export content.
        let eventDetailsAtAdmission = redactedApplicationEventDetails(
            update,
            leasedAccountUID: leasedAccountUID
        )

        applicationUpdateAdmissionsInFlight += 1
''',
    "snapshot account UID before application-update suspension",
)

source = replace_once(
    source,
    '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
''',
    '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            let currentLeasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard currentConnectionToken == token,
                  phase == .observing,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  currentLeasedAccountUID == leasedAccountUID else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "Account/device authority changed while an application receipt was awaiting event custody. The stale callback was not admitted to event history.",
                    kind: "application_event_authority_changed_before_custody"
                )
                return
            }
            var eventDetails = eventDetailsAtAdmission
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
''',
    "revalidate same lease after package awaits",
)

source = replace_once(
    source,
    '''    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return update
        }

        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            redacted[redactedKey] = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
    }
''',
    '''    private func redactedApplicationEventDetails(
        _ update: [String: String],
        leasedAccountUID: String
    ) -> [String: String] {
        let marker = "<redacted-account-uid>"
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let baseKey = key.replacingOccurrences(
                of: leasedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
            // Redaction can collapse two distinct SDK keys onto the same visible spelling.
            // Preserve both pieces of untrusted evidence deterministically instead of silently
            // dropping whichever dictionary element happens to be visited later.
            var redactedKey = baseKey
            var collisionIndex = 2
            while redacted[redactedKey] != nil {
                redactedKey = "\\(baseKey)#\\(collisionIndex)"
                collisionIndex += 1
            }
            redacted[redactedKey] = value.replacingOccurrences(
                of: leasedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
    }
''',
    "explicit account lease redaction helper",
)

ENTRYPOINT.write_text(source)

TEST.write_text('''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("account UID privacy is frozen before async chronology and same lease is rechecked before event custody")
    func acceptedEventFreezesAndRevalidatesExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))

        let leaseCapture = try requiredOffset(containing: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters", in: receiver)
        let privacyFreeze = try requiredOffset(containing: "let eventDetailsAtAdmission = redactedApplicationEventDetails(", in: receiver)
        let packageAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let leaseRecheck = try requiredOffset(containing: "currentLeasedAccountUID == leasedAccountUID", in: receiver)
        let eventLog = try requiredOffset(containing: "log(\"tuya_application_update\", eventDetails)", in: receiver)

        #expect(leaseCapture < privacyFreeze)
        #expect(privacyFreeze < packageAwait)
        #expect(packageAwait < leaseRecheck)
        #expect(leaseRecheck < eventLog)
        #expect(receiver.contains("currentConnectionToken == token"))
        #expect(receiver.contains("phase == .observing"))
        #expect(receiver.contains("accountIdentityLeaseIsAuthorized"))
        #expect(receiver.contains("application_event_authority_changed_before_custody"))
        #expect(!receiver.contains("var eventDetails = redactedApplicationEventDetails(update)"))
    }

    @Test("redaction helper cannot fall back to raw SDK content and preserves redacted-key collisions")
    func redactionHasNoRawFallbackAndPreservesKeyCount() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let helper = String(try section(
            in: receiver,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("leasedAccountUID: String"))
        #expect(helper.contains("key.replacingOccurrences("))
        #expect(helper.contains("value.replacingOccurrences("))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("options: [.caseInsensitive, .literal]"))
        #expect(helper.contains("update.sorted(by:"))
        #expect(helper.contains("while redacted[redactedKey] != nil"))
        #expect(helper.contains("collisionIndex += 1"))
        #expect(!helper.contains("return update"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \\(token)")
            throw Error.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            throw Error.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum Error: Swift.Error { case sectionMissing }
}
''')

final = ENTRYPOINT.read_text()
required = [
    "let eventDetailsAtAdmission = redactedApplicationEventDetails(",
    "leasedAccountUID: leasedAccountUID",
    "currentLeasedAccountUID == leasedAccountUID",
    "application_event_authority_changed_before_custody",
    "while redacted[redactedKey] != nil",
]
for token in required:
    if token not in final:
        raise SystemExit(f"missing required product token: {token}")
receiver = final[final.index("private func receivedApplicationUpdate("):final.index("private func startWatchdog")]
if receiver.index("let eventDetailsAtAdmission") > receiver.index("try await sessionLedger.recordApplicationUpdate"):
    raise SystemExit("privacy projection still occurs after the first suspension point")
helper = receiver[receiver.index("private func redactedApplicationEventDetails("):]
if "return update" in helper:
    raise SystemExit("raw SDK fallback survived account-UID event redaction helper")

SCRIPT.unlink()
WORKFLOW.unlink()
