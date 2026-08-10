from pathlib import Path

APP = Path(__file__).resolve().parents[2] / "NembraApp/App/NembraCaptureEntrypoint.swift"
SNAPSHOT_OLD = "        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n"
SNAPSHOT_NEW = """        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n"""
LOG_OLD = """            var eventDetails = custodySafeUpdate\n            eventDetails[\"generation\"] = String(token.diagnosticGeneration)\n            log(\"tuya_application_update\", eventDetails)\n"""
HELPER_OLD = '''\n    private func redactedApplicationEventDetails(\n        _ update: [String: String],\n        accountUID: String\n    ) -> [String: String] {\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update.sorted(by: { $0.key < $1.key }) {\n            let redactedKey = key.replacingOccurrences(of: accountUID, with: "<redacted-account-uid>", options: [.caseInsensitive, .literal])\n            let redactedValue = value.replacingOccurrences(of: accountUID, with: "<redacted-account-uid>", options: [.caseInsensitive, .literal])\n            var custodyKey = redactedKey\n            var collisionOrdinal = 2\n            while redacted[custodyKey] != nil {\n                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"\n                collisionOrdinal += 1\n            }\n            redacted[custodyKey] = redactedValue\n        }\n        return redacted\n    }\n'''

def once(text, old, new, label):
    if text.count(old) != 1: raise SystemExit(f"{label}: exact match count {text.count(old)}")
    return text.replace(old, new, 1)

def apply():
    s = APP.read_text()
    s = once(s, SNAPSHOT_OLD, SNAPSHOT_NEW, "snapshot")
    s = once(s, LOG_OLD, '            log("tuya_application_update", custodySafeEventDetails)\n', "log")
    s = once(s, HELPER_OLD, "", "helper")
    APP.write_text(s)

def verify():
    s = APP.read_text()
    a = s.index("    private func receivedApplicationUpdate(")
    b = s.index("    private func startWatchdog", a)
    r = s[a:b]
    ordered = [
        "let leasedAccountUID = membershipAccountUID?.trimmingCharacters",
        "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: leasedAccountUID",
        "try await sessionLedger.recordApplicationUpdate",
        "guard currentConnectionToken == token,",
        "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == leasedAccountUID",
        "log(\"tuya_application_update\", custodySafeEventDetails)",
    ]
    p = [r.index(x) for x in ordered]
    if p != sorted(p): raise SystemExit("custody ordering regressed")
    for x in ('redactedApplicationEventDetails(', 'eventDetails["generation"] =', 'update.merging(['):
        if x in r: raise SystemExit(f"lossy path remains: {x}")
    for x in ('redactedApplicationDescription', 'NembraTuyaPrivateIdentity.appSecret', 'liveTransportDriver.isLocallyConnected'):
        if x not in s: raise SystemExit(f"current dependency missing: {x}")

if __name__ == "__main__":
    import sys
    apply() if sys.argv[1] == "apply" else verify()
