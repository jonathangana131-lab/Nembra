#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")


def replace_exact(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one source match, found {count}")
    source = source.replace(old, new, 1)


replace_exact(
    '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
''',
    '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        // Snapshot the exact account identity while the admission checks above are still
        // synchronously true. The actor hops below may interleave foreground/account teardown;
        // export custody must never re-read mutable membership state after that suspension.
        guard let leasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !leasedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity disappeared before application evidence could enter export custody.",
                kind: "sdk_account_identity_missing_before_application_custody"
            )
            return
        }
        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)

        do {
''',
    "snapshot account UID before first suspension",
)

replace_exact(
    '''            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
''',
    '''            var eventDetails = custodySafeUpdate
            eventDetails["generation"] = String(token.diagnosticGeneration)
''',
    "consume admission-bound sanitized event",
)

replace_exact(
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
        accountUID: String
    ) -> [String: String] {
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            // Redacting malformed keys can collapse two distinct SDK entries onto one key.
            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.
            var custodyKey = redactedKey
            var collisionOrdinal = 2
            while redacted[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            redacted[custodyKey] = redactedValue
        }
        return redacted
    }
''',
    "make UID redaction snapshot-bound and collision preserving",
)

receiver_start = source.index("private func receivedApplicationUpdate(")
receiver_end = source.index("private func startWatchdog", receiver_start)
receiver = source[receiver_start:receiver_end]
lease = receiver.index("let leasedAccountUID = membershipAccountUID?.trimmingCharacters")
custody = receiver.index("let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)")
ledger = receiver.index("try await sessionLedger.recordApplicationUpdate")
assert lease < custody < ledger
assert "var eventDetails = custodySafeUpdate" in receiver
assert 'eventDetails["generation"] = String(token.diagnosticGeneration)' in receiver

helper_start = receiver.index("private func redactedApplicationEventDetails(")
helper = receiver[helper_start:]
assert "accountUID: String" in helper
assert "membershipAccountUID" not in helper
assert "return update" not in helper
assert "update.sorted" in helper
assert "collisionOrdinal" in helper
assert "while redacted[custodyKey] != nil" in helper
assert "redacted[custodyKey] = redactedValue" in helper

path.write_text(source, encoding="utf-8")
