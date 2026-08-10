#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text(encoding="utf-8")

old_guard = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
'''
new_guard = '''        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty,
              let driver else {
'''
if source.count(old_guard) != 1:
    raise SystemExit(f"expected one application admission source-authority guard, found {source.count(old_guard)}")
source = source.replace(old_guard, new_guard, 1)

old_log = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
new_log = '''            let eventDetails = makeApplicationEventDetails(
                update,
                verifiedAccountUID: verifiedAccountUID,
                token: token
            )
            log("tuya_application_update", eventDetails)
'''
if source.count(old_log) != 1:
    raise SystemExit(f"expected one untrusted-first application event merge, found {source.count(old_log)}")
source = source.replace(old_log, new_log, 1)

start_watchdog = '    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {'
helper = '''    private func makeApplicationEventDetails(
        _ update: [String: String],
        verifiedAccountUID: String,
        token: TuyaReadOnlyConnectionToken
    ) -> [String: String] {
        var eventDetails: [String: String] = [:]
        eventDetails.reserveCapacity(update.count + 1)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: verifiedAccountUID,
                with: "<redacted-account-uid>",
                options: [.literal]
            )
            eventDetails[redactedKey] = redactedValue
        }

        // Nembra-owned provenance is written after untrusted application evidence so an SDK
        // payload cannot impersonate the accepted package connection generation.
        eventDetails["generation"] = String(token.diagnosticGeneration)
        return eventDetails
    }

'''
if source.count(start_watchdog) != 1:
    raise SystemExit(f"expected one watchdog insertion point, found {source.count(start_watchdog)}")
source = source.replace(start_watchdog, helper + start_watchdog, 1)

old_duplicates = '''        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "sessionkey",
        "authkey",
'''
new_duplicates = '''        "accounttoken",
        "accesstoken",
        "refreshtoken",
        "authkey",
'''
if source.count(old_duplicates) != 1:
    raise SystemExit(f"expected one duplicate sessionkey classifier suffix, found {source.count(old_duplicates)}")
source = source.replace(old_duplicates, new_duplicates, 1)

path.write_text(source, encoding="utf-8")

receiver_start = source.index("    private func receivedApplicationUpdate(")
watchdog_start = source.index(start_watchdog, receiver_start)
receiver = source[receiver_start:watchdog_start]
helper_start = source.index("    private func makeApplicationEventDetails(", receiver_start)
custody = source[helper_start:watchdog_start]

required_receiver = (
    "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
    "!verifiedAccountUID.isEmpty",
    "let eventDetails = makeApplicationEventDetails(",
    "verifiedAccountUID: verifiedAccountUID",
    'log("tuya_application_update", eventDetails)',
)
for needle in required_receiver:
    if needle not in receiver:
        raise SystemExit(f"missing event-custody admission invariant: {needle}")
if 'log("tuya_application_update", update' in receiver or "update.merging([" in receiver:
    raise SystemExit("untrusted SDK application dictionary still enters event log directly")

required_custody = (
    "var eventDetails: [String: String] = [:]",
    "let redactedKey",
    "let redactedValue",
    "of: verifiedAccountUID",
    'with: "<redacted-account-uid>"',
    'eventDetails["generation"] = String(token.diagnosticGeneration)',
)
for needle in required_custody:
    if needle not in custody:
        raise SystemExit(f"missing event-custody helper invariant: {needle}")
if custody.index("eventDetails[redactedKey] = redactedValue") > custody.index('eventDetails["generation"] = String(token.diagnosticGeneration)'):
    raise SystemExit("trusted generation must be assigned after untrusted application evidence")

driver_start = source.index("@MainActor\nprivate final class SmartLifeDriver")
driver_end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", driver_start)
driver = source[driver_start:driver_end]
if driver.count('"sessionkey"') != 1:
    raise SystemExit("shared application secret classifier should contain exactly one sessionkey fragment")
if '"uid",' in driver or '"uid"\n' in driver:
    raise SystemExit("account UID custody must not blanket-suppress generic uid keys")
for forbidden in ("publishDps", "queryDps", "writeValue"):
    if forbidden in receiver or forbidden in custody:
        raise SystemExit(f"event-custody lane gained forbidden protocol authority: {forbidden}")

print("application event provenance + account UID custody: PASS")
