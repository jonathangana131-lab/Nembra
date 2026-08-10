from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

OLD = '''        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            var eventDetails = custodySafeUpdate\n            eventDetails["generation"] = String(token.diagnosticGeneration)\n            log("tuya_application_update", eventDetails)\n'''
NEW = '''        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log("tuya_application_update", custodySafeEventDetails)\n'''
HELPER = '''\n    private func redactedApplicationEventDetails(\n        _ update: [String: String],\n        accountUID: String\n    ) -> [String: String] {\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update.sorted(by: { $0.key < $1.key }) {\n            let redactedKey = key.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n            let redactedValue = value.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n\n            // Redacting malformed keys can collapse two distinct SDK entries onto one key.\n            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.\n            var custodyKey = redactedKey\n            var collisionOrdinal = 2\n            while redacted[custodyKey] != nil {\n                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"\n                collisionOrdinal += 1\n            }\n            redacted[custodyKey] = redactedValue\n        }\n        return redacted\n    }\n'''

def once(text, old, new, label):
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one exact match, found {text.count(old)}")
    return text.replace(old, new, 1)

def receiver(source):
    a = source.index("    private func receivedApplicationUpdate(")
    b = source.index("    private func startWatchdog", a)
    return source[a:b]

def apply():
    source = APP.read_text()
    source = once(source, OLD, NEW, "event receiver")
    source = once(source, HELPER, "", "inline helper")
    APP.write_text(source)

def verify():
    source = APP.read_text()
    scoped = receiver(source)
    ordered = [
        "let leasedAccountUID = membershipAccountUID?.trimmingCharacters",
        "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: leasedAccountUID",
        "try await sessionLedger.recordApplicationUpdate",
        "log(\"tuya_application_update\", custodySafeEventDetails)",
    ]
    offsets = [scoped.index(token) for token in ordered]
    if offsets != sorted(offsets):
        raise SystemExit("event custody ordering is not admission-bound")
    post_await = scoped[offsets[4]:]
    if "membershipAccountUID" in post_await:
        raise SystemExit("mutable account identity reread after suspension")
    for token in ("redactedApplicationEventDetails(", "eventDetails[\"generation\"] =", "update.merging(["):
        if token in scoped:
            raise SystemExit(f"lossy legacy custody remains: {token}")
    for token in (
        "guard phase != .accepted else { return }",
        "foreground_integrity_lost_after_target_correlation",
        "applicationUpdateAdmissionsInFlight += 1",
    ):
        if token not in source:
            raise SystemExit(f"a7a28 dependency missing: {token}")

if __name__ == "__main__":
    import sys
    apply() if sys.argv[1] == "apply" else verify()
