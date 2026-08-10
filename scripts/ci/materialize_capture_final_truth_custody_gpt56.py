#!/usr/bin/env python3
from pathlib import Path

PATH = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = PATH.read_text(encoding="utf-8")

membership_before = """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipRequestID = UUID()
"""
membership_after = """        sdkDeviceMembershipVerified = false
        membershipAccountUID = nil
        membershipDeviceID = nil
        membershipStatus = \"Exact scooter membership must be freshly verified for this Secure Link foreground/view lifetime before Bluetooth discovery.\"
        membershipRequestID = UUID()
"""
if source.count(membership_before) != 2:
    raise SystemExit(f"expected exactly two membership revocation blocks, found {source.count(membership_before)}")
source = source.replace(membership_before, membership_after)

source_authority_before = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
"""
source_authority_after = """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID,
              !verifiedAccountUID.isEmpty,
              let driver else {
"""
if source.count(source_authority_before) != 1:
    raise SystemExit("expected exactly one application-update authority guard")
source = source.replace(source_authority_before, source_authority_after, 1)

log_before = """            log(\"tuya_application_update\", update.merging([
                \"generation\": String(token.diagnosticGeneration)
            ]) { current, _ in current })
"""
log_after = """            let sanitizedUpdate = redactVerifiedAccountUID(
                in: update,
                verifiedAccountUID: verifiedAccountUID
            )
            log(\"tuya_application_update\", sanitizedUpdate.merging([
                \"generation\": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
"""
if source.count(log_before) != 1:
    raise SystemExit("expected exactly one untrusted-first application-event merge")
source = source.replace(log_before, log_after, 1)

watchdog_marker = """    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {
"""
uid_helper = """    private func redactVerifiedAccountUID(
        in update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let marker = \"<redacted-account-uid>\"
        var redacted: [String: String] = [:]

        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            var safeKey = key.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )
            let safeValue = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: marker,
                options: [.caseInsensitive, .literal]
            )

            if redacted[safeKey] != nil {
                var suffix = 2
                while redacted[\"\\(safeKey)#\\(suffix)\"] != nil { suffix += 1 }
                safeKey = \"\\(safeKey)#\\(suffix)\"
            }
            redacted[safeKey] = safeValue
        }
        return redacted
    }

"""
if source.count(watchdog_marker) != 1:
    raise SystemExit("expected exactly one watchdog insertion marker")
source = source.replace(watchdog_marker, uid_helper + watchdog_marker, 1)

start = source.index("@MainActor\nprivate final class SmartLifeDriver")
end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
driver = source[start:end]
needle = '        "sessionkey",\n'
if driver.count(needle) != 2:
    raise SystemExit(f"expected exactly two SmartLifeDriver sessionkey entries, found {driver.count(needle)}")
first = driver.index(needle)
second = driver.index(needle, first + len(needle))
driver = driver[:second] + driver[second + len(needle):]
source = source[:start] + driver + source[end:]

# Fail-closed postconditions for the exact intended product delta.
if source.count(membership_after) != 2:
    raise SystemExit("membership status reset was not materialized twice")
if '<redacted-account-uid>' not in source:
    raise SystemExit("account UID redaction marker missing")
if 'log("tuya_application_update", update.merging([' in source:
    raise SystemExit("raw application update still reaches event merge")
if ') { current, _ in current })' in source:
    raise SystemExit("untrusted application metadata can still win a collision")
if ') { _, trusted in trusted })' not in source:
    raise SystemExit("trusted event provenance merge missing")
start = source.index("@MainActor\nprivate final class SmartLifeDriver")
end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", start)
driver = source[start:end]
if driver.count(needle) != 1:
    raise SystemExit("SmartLifeDriver sessionkey classifier was not simplified to one entry")
if '        "uid",' in driver or '        "uid"\n' in driver:
    raise SystemExit("generic uid key filtering is forbidden")

PATH.write_text(source, encoding="utf-8")
