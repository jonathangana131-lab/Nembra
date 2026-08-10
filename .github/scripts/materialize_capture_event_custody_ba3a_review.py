#!/usr/bin/env python3
from pathlib import Path
import subprocess

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
EXPECTED_BLOB = "d3075d4fe7bc96ff11079d9f54982ca4c8d90746"
source = PATH.read_text(encoding="utf-8")
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
              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty,
              let driver else {
"""
if source.count(guard_before) != 1:
    raise SystemExit(f"expected one application source-authority guard, found {source.count(guard_before)}")
source = source.replace(guard_before, guard_after, 1)

call_before = """            var eventDetails = redactedApplicationEventDetails(update)
"""
call_after = """            var eventDetails = redactedApplicationEventDetails(
                update,
                verifiedAccountUID: verifiedAccountUID
            )
"""
if source.count(call_before) != 1:
    raise SystemExit(f"expected one application event scrub call, found {source.count(call_before)}")
source = source.replace(call_before, call_after, 1)

helper_before = """    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
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
"""
helper_after = """    private func redactedApplicationEventDetails(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
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
    raise SystemExit("expected exact ba3a event redactor")
source = source.replace(helper_before, helper_after, 1)

receiver_start = source.index("    private func receivedApplicationUpdate(")
helper_start = source.index("    private func redactedApplicationEventDetails", receiver_start)
receiver = source[receiver_start:helper_start]
helper_end = source.index("    private func startWatchdog", helper_start)
helper = source[helper_start:helper_end]

capture_i = receiver.index("let verifiedAccountUID = membershipAccountUID")
first_await_i = receiver.index("try await sessionLedger.recordApplicationUpdate")
call_i = receiver.index("verifiedAccountUID: verifiedAccountUID")
if not capture_i < first_await_i < call_i:
    raise SystemExit("verified account UID is not captured before the first application-admission suspension point")
if "membershipAccountUID" in helper:
    raise SystemExit("event redactor still reads mutable membership state after suspension")
if "return update" in helper:
    raise SystemExit("event redactor remains fail-open")
if "update.sorted(by: { $0.key < $1.key })" not in helper:
    raise SystemExit("event redaction key-collision ordering is not deterministic")
if "if redacted[redactedKey] != nil" not in helper or "var suffix = 2" not in helper:
    raise SystemExit("redacted-key collisions are still lossy")
if 'eventDetails["generation"] = String(token.diagnosticGeneration)' not in receiver:
    raise SystemExit("trusted generation provenance assignment was lost")
if 'log("tuya_application_update", update' in receiver:
    raise SystemExit("raw application update still reaches immutable logging")

PATH.write_text(source, encoding="utf-8")
