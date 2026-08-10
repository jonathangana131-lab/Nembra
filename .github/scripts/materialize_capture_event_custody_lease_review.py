#!/usr/bin/env python3
from pathlib import Path

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = PATH.read_text(encoding="utf-8")

# This review is intentionally exact-head. Fail closed if the donor shape moved.
EXPECTED_BLOB = "574bc88707b549590b5e02748691fa2f1b4449c4"
import subprocess
actual_blob = subprocess.check_output(["git", "hash-object", str(PATH)], text=True).strip()
if actual_blob != EXPECTED_BLOB:
    raise SystemExit(f"unexpected Capture entrypoint blob: {actual_blob}")

guard_before = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
"""
guard_after = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID,
              !verifiedAccountUID.isEmpty,
              let driver else {
"""
if source.count(guard_before) != 1:
    raise SystemExit(f"expected one application source-authority guard, found {source.count(guard_before)}")
source = source.replace(guard_before, guard_after, 1)

call_before = """            let exportSafeUpdate = redactedApplicationUpdateForEventCustody(update)
"""
call_after = """            let exportSafeUpdate = redactedApplicationUpdateForEventCustody(
                update,
                verifiedAccountUID: verifiedAccountUID
            )
"""
if source.count(call_before) != 1:
    raise SystemExit(f"expected one late UID scrub call, found {source.count(call_before)}")
source = source.replace(call_before, call_after, 1)

helper_before = """    private func redactedApplicationUpdateForEventCustody(_ update: [String: String]) -> [String: String] {
        guard let rawAccountUID = membershipAccountUID else { return [:] }
        let accountUID = rawAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return [:] }

        var redacted: [String: String] = [:]
        for (key, value) in update {
            var redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            if redacted[redactedKey] != nil {
                var suffix = 2
                while redacted["\\(redactedKey)#\\(suffix)"] != nil {
                    suffix += 1
                }
                redactedKey = "\\(redactedKey)#\\(suffix)"
            }
            redacted[redactedKey] = redactedValue
        }
        return redacted
    }
"""
helper_after = """    private func redactedApplicationUpdateForEventCustody(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        var redacted: [String: String] = [:]
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            var redactedKey = key.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            if redacted[redactedKey] != nil {
                var suffix = 2
                while redacted["\\(redactedKey)#\\(suffix)"] != nil {
                    suffix += 1
                }
                redactedKey = "\\(redactedKey)#\\(suffix)"
            }
            redacted[redactedKey] = redactedValue
        }
        return redacted
    }
"""
if source.count(helper_before) != 1:
    raise SystemExit("expected exact donor account-UID scrubber")
source = source.replace(helper_before, helper_after, 1)

start_token = "@MainActor\nprivate final class SmartLifeDriver"
end_token = "#endif\n\nprivate enum AppleAccountAuthorizationError"
start = source.index(start_token)
end = source.index(end_token, start)
driver = source[start:end]
session_key_line = '        "sessionkey",\n'
if driver.count(session_key_line) != 2:
    raise SystemExit(f"expected two donor sessionkey entries, found {driver.count(session_key_line)}")
first = driver.index(session_key_line)
second = driver.index(session_key_line, first + len(session_key_line))
driver = driver[:second] + driver[second + len(session_key_line):]
source = source[:start] + driver + source[end:]

# Fail-closed semantic postconditions.
receiver_start = source.index("    private func receivedApplicationUpdate(")
helper_start = source.index("    private func redactedApplicationUpdateForEventCustody", receiver_start)
receiver = source[receiver_start:helper_start]
helper_end = source.index("    private func startWatchdog", helper_start)
helper = source[helper_start:helper_end]

capture_i = receiver.index("let verifiedAccountUID = membershipAccountUID")
first_await_i = receiver.index("try await sessionLedger.recordApplicationUpdate")
call_i = receiver.index("verifiedAccountUID: verifiedAccountUID")
if not capture_i < first_await_i < call_i:
    raise SystemExit("account UID is not bound before the first application-admission suspension point")
if "membershipAccountUID" in helper:
    raise SystemExit("event scrubber still reads mutable membership state after suspension")
if "update.sorted(by: { $0.key < $1.key })" not in helper:
    raise SystemExit("event custody collision ordering is not deterministic")
if ') { _, trusted in trusted })' not in receiver:
    raise SystemExit("trusted generation provenance precedence was lost")
if 'log("tuya_application_update", update.merging([' in receiver:
    raise SystemExit("raw application dictionary still reaches immutable event logging")

start = source.index(start_token)
end = source.index(end_token, start)
driver = source[start:end]
if driver.count(session_key_line) != 1:
    raise SystemExit("SmartLifeDriver sessionkey classifier did not simplify to one entry")
if '        "uid",' in driver or '        "uid"\n' in driver:
    raise SystemExit("generic uid-key suppression is forbidden; custody must stay exact-value-bound")

PATH.write_text(source, encoding="utf-8")
