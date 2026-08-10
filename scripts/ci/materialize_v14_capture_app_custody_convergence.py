#!/usr/bin/env python3
from pathlib import Path

ENTRY = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
UID_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")

source = ENTRY.read_text()

# Simplify the existing credential classifier without changing its set of meanings.
duplicate_fragments = '''        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
        "seckey",
'''
single_fragments = '''        "localkey",
        "sessionkey",
        "appkey",
        "appsecret",
        "password",
        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
        "seckey",
'''
if source.count(duplicate_fragments) != 1:
    raise SystemExit("secret-fragment list no longer matches the exact reviewed product")
source = source.replace(duplicate_fragments, single_fragments, 1)

marker = "    private func receivedApplicationUpdate(\n"
if source.count(marker) != 1:
    raise SystemExit("receivedApplicationUpdate marker mismatch")

helper = '''    private func sanitizedApplicationEventDetails(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String]? {
        let uid = verifiedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else { return nil }

        let redactionMarker = "<redacted-account-uid>"
        var sanitized: [String: String] = [:]
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(of: uid, with: redactionMarker)
            let redactedValue = value.replacingOccurrences(of: uid, with: redactionMarker)

            // Malformed keys can collapse after UID redaction. Preserve every opaque application
            // field under a deterministic non-secret suffix instead of silently dropping evidence.
            var custodyKey = redactedKey
            var suffix = 2
            while sanitized[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(suffix)"
                suffix += 1
            }
            sanitized[custodyKey] = redactedValue
        }
        return sanitized
    }

'''
source = source.replace(marker, helper + marker, 1)

start = source.index("    private func receivedApplicationUpdate(")
end = source.index("    private func startWatchdog", start)
receiver = source[start:end]

authority = '''        guard sdkAccountLoggedIn,
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
'''
authority_repair = '''        guard sdkAccountLoggedIn,
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
              !verifiedAccountUID.isEmpty,
              currentAccountUID == verifiedAccountUID,
              let sanitizedUpdate = sanitizedApplicationEventDetails(
                  update,
                  verifiedAccountUID: verifiedAccountUID
              ) else {
            await invalidateSourceAuthority(
                token: token,
                message: "Exact same-account UID custody became unavailable before application evidence could enter accepted event storage.",
                kind: "sdk_account_uid_custody_unavailable"
            )
            return
        }
        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
'''
if receiver.count(authority) != 1:
    raise SystemExit("application authority block no longer matches exact reviewed product")
receiver = receiver.replace(authority, authority_repair, 1)

logging = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)
            await refreshLedgerSnapshot()
            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
logging_repair = '''            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)

            // The ledger call crosses an actor boundary. Re-prove exact source/account custody
            // before publishing that receipt into the app-visible snapshot or immutable event log.
            guard currentConnectionToken == token,
                  phase == .observing,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  membershipAccountUID == verifiedAccountUID,
                  currentAccountUID == verifiedAccountUID else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "SDK account/device source authority changed while application evidence was entering package chronology.",
                    kind: "sdk_source_authority_changed_during_application_admission"
                )
                return
            }

            await refreshLedgerSnapshot()
            guard currentConnectionToken == token,
                  phase == .observing,
                  sdkAccountLoggedIn,
                  sdkDeviceMembershipVerified,
                  accountIdentityLeaseIsAuthorized,
                  membershipAccountUID == verifiedAccountUID,
                  currentAccountUID == verifiedAccountUID else {
                await invalidateSourceAuthority(
                    token: token,
                    message: "SDK account/device source authority changed before application evidence could enter accepted event storage.",
                    kind: "sdk_source_authority_changed_before_application_event_custody"
                )
                return
            }

            log("tuya_application_update", sanitizedUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
'''
if receiver.count(logging) != 1:
    raise SystemExit("application event logging block no longer matches exact reviewed product")
receiver = receiver.replace(logging, logging_repair, 1)
source = source[:start] + receiver + source[end:]
ENTRY.write_text(source)

# Strengthen the absorbed account-UID red contract for malformed UID-bearing keys and collision
# preservation. This remains a source contract; exact app compilation is required separately.
uid_test = UID_TEST.read_text()
needle = '''        #expect(source.contains("<redacted-account-uid>"))
        #expect(!updateAdmission.contains("log(\\"tuya_application_update\\", update.merging(["))
'''
replacement = '''        #expect(source.contains("<redacted-account-uid>"))
        #expect(!updateAdmission.contains("log(\\"tuya_application_update\\", update.merging(["))

        let sanitizer = String(try section(
            in: source,
            from: "private func sanitizedApplicationEventDetails(",
            to: "private func receivedApplicationUpdate("
        ))
        #expect(sanitizer.contains("key.replacingOccurrences(of: uid, with: redactionMarker)"))
        #expect(sanitizer.contains("value.replacingOccurrences(of: uid, with: redactionMarker)"))
        #expect(sanitizer.contains("while sanitized[custodyKey] != nil"))
        #expect(updateAdmission.contains("membershipAccountUID == verifiedAccountUID"))
        #expect(updateAdmission.contains("currentAccountUID == verifiedAccountUID"))
'''
if uid_test.count(needle) != 1:
    raise SystemExit("account-UID red contract no longer matches pinned donor")
UID_TEST.write_text(uid_test.replace(needle, replacement, 1))

# Fail-fast semantic source assertions before SwiftPM executes the absorbed contracts.
final_source = ENTRY.read_text()
assert final_source.count('"sessionkey",') == 1
assert '<redacted-account-uid>' in final_source
assert 'sanitizedUpdate.merging([' in final_source
assert ']) { _, trusted in trusted })' in final_source
assert 'log("tuya_application_update", update.merging([' not in final_source
assert 'key.replacingOccurrences(of: uid, with: redactionMarker)' in final_source
assert 'value.replacingOccurrences(of: uid, with: redactionMarker)' in final_source
