from pathlib import Path

SOURCE = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
text = SOURCE.read_text()


def replace_once(haystack: str, old: str, new: str, label: str) -> str:
    count = haystack.count(old)
    if count != 1:
        raise SystemExit(f"{label} anchor drifted: {count}")
    return haystack.replace(old, new, 1)


def replace_in_section(source: str, start: str, end: str, old: str, new: str, label: str) -> str:
    start_index = source.index(start)
    end_index = source.index(end, start_index)
    section = source[start_index:end_index]
    section = replace_once(section, old, new, label)
    return source[:start_index] + section + source[end_index:]

receiver_old = '''        guard sdkAccountLoggedIn,
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
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
            message = "Receiving same-generation scooter application data · \\(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
'''
receiver_new = '''        guard sdkAccountLoggedIn,
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
        guard let verifiedAccountUID = membershipAccountUID, !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "The verified Tuya account-identity lease disappeared before application evidence custody.",
                kind: "sdk_account_identity_lease_missing_during_application_update"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            let redactedUpdate = redactVerifiedAccountUID(update, verifiedAccountUID: verifiedAccountUID)
            log("tuya_application_update", redactedUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
            message = "Receiving same-generation scooter application data · \\(applicationUpdateCount) update(s). Canonical readiness still depends on the sealed observation horizon."
'''
text = replace_in_section(
    text,
    "    private func receivedApplicationUpdate(",
    "    private func startWatchdog",
    receiver_old,
    receiver_new,
    "application event custody",
)

helper = '''
    private func redactVerifiedAccountUID(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let marker = "<redacted-account-uid>"
        var redacted: [String: String] = [:]
        for key in update.keys.sorted() {
            guard let value = update[key] else { continue }
            let redactedKey = key.replacingOccurrences(of: verifiedAccountUID, with: marker)
            let redactedValue = value.replacingOccurrences(of: verifiedAccountUID, with: marker)

            // Redaction can collapse two malformed keys onto one safe spelling. Preserve both
            // evidence values without ever restoring the verified account UID into the key.
            var admittedKey = redactedKey
            var collisionIndex = 2
            while redacted[admittedKey] != nil {
                admittedKey = "\\(redactedKey)#\\(collisionIndex)"
                collisionIndex += 1
            }
            redacted[admittedKey] = redactedValue
        }
        return redacted
    }

'''
watchdog_anchor = "    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {\n"
if text.count(watchdog_anchor) != 1:
    raise SystemExit("watchdog insertion anchor drifted")
if "private func redactVerifiedAccountUID(" in text:
    raise SystemExit("account UID helper already exists")
text = text.replace(watchdog_anchor, helper + watchdog_anchor, 1)

duplicate_session = '''        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
'''
simplified_session = '''        "accesstoken",
        "refreshtoken",
        "authkey",
'''
text = replace_once(text, duplicate_session, simplified_session, "duplicate sessionkey")

SOURCE.write_text(text)

updated = SOURCE.read_text()
controller = updated[updated.index("private final class SecureLinkController"):updated.index("@MainActor\nprivate protocol OfficialTuyaDriver")]
receiver = controller[controller.index("private func receivedApplicationUpdate("):controller.index("private func startWatchdog")]
assert "verifiedAccountUID" in receiver
assert "redactVerifiedAccountUID(update" in receiver
assert ") { _, trusted in trusted })" in receiver
assert ") { current, _ in current })" not in receiver
assert "<redacted-account-uid>" in controller
assert "key.replacingOccurrences(of: verifiedAccountUID" in controller
assert "value.replacingOccurrences(of: verifiedAccountUID" in controller
driver = updated[updated.index("@MainActor\nprivate final class SmartLifeDriver"):updated.index("#endif\n\nprivate enum AppleAccountAuthorizationError")]
assert driver.count('"sessionkey"') == 1
assert '"uid",' not in driver
print("materialized Capture application-event custody convergence")
