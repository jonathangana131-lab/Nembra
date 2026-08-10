from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


receiver_start = source.index("    private func receivedApplicationUpdate(\n")
receiver_end = source.index("    private func redactedApplicationEventDetails(", receiver_start)
receiver = source[receiver_start:receiver_end]

old_guard = '''        guard sdkAccountLoggedIn,
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
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {'''
new_guard = '''        guard sdkAccountLoggedIn,
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
                message: "Verified Tuya account identity was unavailable before application evidence custody.",
                kind: "sdk_account_uid_authority_missing_during_observation"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {'''
receiver = replace_once(receiver, old_guard, new_guard, "pre-await leased UID capture")

old_custody = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)'''
new_custody = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()

            // The actor hops above can interleave account/view lifecycle changes. Re-earn the exact
            // token + account lease immediately before immutable event custody; a stale callback
            // must never enter a later attempt or fall back to unsanitized application content.
            guard currentConnectionToken == token,
                  phase == .observing,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == verifiedAccountUID else {
                if currentConnectionToken == token {
                    await invalidateSourceAuthority(
                        token: token,
                        message: "SDK account/device authority changed before application evidence could enter event custody.",
                        kind: "sdk_source_authority_changed_before_application_event_custody"
                    )
                }
                return
            }

            var eventDetails = redactedApplicationEventDetails(
                update,
                verifiedAccountUID: verifiedAccountUID
            )
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)'''
receiver = replace_once(receiver, old_custody, new_custody, "post-await authority fence")
source = source[:receiver_start] + receiver + source[receiver_end:]

redactor_start = source.index("    private func redactedApplicationEventDetails(")
redactor_end = source.index("    private func startWatchdog", redactor_start)
old_redactor = source[redactor_start:redactor_end]
expected_old_redactor = '''    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
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

'''
if old_redactor != expected_old_redactor:
    raise SystemExit("account UID redactor no longer matches exact ba3a product source")
new_redactor = '''    private func redactedApplicationEventDetails(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let accountUID = verifiedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return [:] }

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

            // Redaction can collapse two malformed keys to the same spelling. Keep both opaque
            // values deterministically without reintroducing the sensitive original identifier.
            var admittedKey = redactedKey
            var collisionOrdinal = 2
            while redacted[admittedKey] != nil {
                admittedKey = "\\(redactedKey)#\\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            redacted[admittedKey] = redactedValue
        }
        return redacted
    }

'''
source = source[:redactor_start] + new_redactor + source[redactor_end:]
path.write_text(source, encoding="utf-8")

materialized = path.read_text(encoding="utf-8")
assert "sdk_account_uid_authority_missing_during_observation" in materialized
assert "sdk_source_authority_changed_before_application_event_custody" in materialized
assert "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == verifiedAccountUID" in materialized
assert "verifiedAccountUID: verifiedAccountUID" in materialized
assert "guard !accountUID.isEmpty else { return [:] }" in materialized
assert "return update" not in materialized[materialized.index("    private func redactedApplicationEventDetails("):materialized.index("    private func startWatchdog")]
print("post-await application event custody materialization: PASS")
