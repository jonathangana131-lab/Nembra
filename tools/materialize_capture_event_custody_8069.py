#!/usr/bin/env python3
from pathlib import Path

path = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
source = path.read_text()


def replace_exact(old: str, new: str, label: str) -> None:
    global source
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one source match, found {count}")
    source = source.replace(old, new, 1)


replace_exact(
    '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        do {
''',
    '''        applicationUpdateAdmissionsInFlight += 1
        defer { applicationUpdateAdmissionsInFlight -= 1 }

        guard let leasedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !leasedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity disappeared before application evidence could enter export custody.",
                kind: "sdk_account_identity_missing_before_application_custody"
            )
            return
        }
        let accountUIDRedactionMarker = "<redacted-account-uid>"
        var custodySafeUpdate: [String: String] = [:]
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(
                of: leasedAccountUID,
                with: accountUIDRedactionMarker,
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: leasedAccountUID,
                with: accountUIDRedactionMarker,
                options: [.caseInsensitive, .literal]
            )
            var custodyKey = redactedKey
            var collisionOrdinal = 2
            while custodySafeUpdate[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"
                collisionOrdinal += 1
            }
            custodySafeUpdate[custodyKey] = redactedValue
        }

        do {
''',
    "account UID key/value custody",
)

replace_exact(
    '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
''',
    '''            log("tuya_application_update", custodySafeUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
''',
    "trusted event generation precedence",
)

replace_exact(
    '''        "refreshtoken",
        "sessionkey",
        "authkey",
''',
    '''        "refreshtoken",
        "authkey",
''',
    "duplicate sessionkey classifier entry",
)

receiver_start = source.index("private func receivedApplicationUpdate(")
receiver_end = source.index("private func startWatchdog", receiver_start)
receiver = source[receiver_start:receiver_end]
assert "leasedAccountUID" in receiver
assert "<redacted-account-uid>" in receiver
assert "redactedKey" in receiver and "redactedValue" in receiver
assert receiver.count("replacingOccurrences(") >= 2
assert receiver.index("custodySafeUpdate") < receiver.index("sessionLedger.recordApplicationUpdate")
assert ') { _, trusted in trusted })' in receiver
assert ') { current, _ in current })' not in receiver
assert 'log("tuya_application_update", update.merging([' not in receiver
assert "while custodySafeUpdate[custodyKey] != nil" in receiver
assert "custodySafeUpdate[custodyKey] = redactedValue" in receiver

driver_start = source.index("private final class SmartLifeDriver")
driver_end = source.index("private enum AppleAccountAuthorizationError", driver_start)
driver = source[driver_start:driver_end]
assert driver.count('"sessionkey"') == 1
assert '"uid",' not in driver

path.write_text(source)
