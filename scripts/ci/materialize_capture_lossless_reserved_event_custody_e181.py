from pathlib import Path

APP = Path(__file__).resolve().parents[2] / "NembraApp/App/NembraCaptureEntrypoint.swift"
SNAPSHOT_OLD = "        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n"
SNAPSHOT_NEW = """        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n"""
LOG_OLD = """            var eventDetails = custodySafeUpdate\n            eventDetails[\"generation\"] = String(token.diagnosticGeneration)\n            log(\"tuya_application_update\", eventDetails)\n"""
LOG_NEW = '            log("tuya_application_update", custodySafeEventDetails)\n'

def once(text, old, new, label):
    if text.count(old) != 1:
        raise SystemExit(f"{label}: exact match count {text.count(old)}")
    return text.replace(old, new, 1)

def apply():
    s = APP.read_text()
    s = once(s, SNAPSHOT_OLD, SNAPSHOT_NEW, "snapshot")
    s = once(s, LOG_OLD, LOG_NEW, "log")
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
    if p != sorted(p):
        raise SystemExit("custody ordering regressed")
    for x in ('redactedApplicationEventDetails(update, accountUID:', 'eventDetails["generation"] =', 'update.merging(['):
        if x in r:
            raise SystemExit(f"lossy path remains in accepted receiver: {x}")
    for x in ('redactedApplicationDescription', 'NembraTuyaPrivateIdentity.appSecret', 'liveTransportDriver.isLocallyConnected'):
        if x not in s:
            raise SystemExit(f"current dependency missing: {x}")

if __name__ == "__main__":
    import sys
    apply() if sys.argv[1] == "apply" else verify()
