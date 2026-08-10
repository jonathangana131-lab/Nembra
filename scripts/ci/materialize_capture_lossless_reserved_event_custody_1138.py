from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"

SNAPSHOT_OLD = "        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n"
SNAPSHOT_NEW = """        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n"""
LOG_OLD = """            var eventDetails = custodySafeUpdate\n            eventDetails[\"generation\"] = String(token.diagnosticGeneration)\n            log(\"tuya_application_update\", eventDetails)\n"""
LOG_NEW = "            log(\"tuya_application_update\", custodySafeEventDetails)\n"
HELPER_OLD = '''\n    private func redactedApplicationEventDetails(\n        _ update: [String: String],\n        accountUID: String\n    ) -> [String: String] {\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update.sorted(by: { $0.key < $1.key }) {\n            let redactedKey = key.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n            let redactedValue = value.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n\n            // Redacting malformed keys can collapse two distinct SDK entries onto one key.\n            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.\n            var custodyKey = redactedKey\n            var collisionOrdinal = 2\n            while redacted[custodyKey] != nil {\n                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"\n                collisionOrdinal += 1\n            }\n            redacted[custodyKey] = redactedValue\n        }\n        return redacted\n    }\n'''

def once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)

def receiver(source):
    a = source.index("    private func receivedApplicationUpdate(")
    b = source.index("    private func startWatchdog", a)
    return source[a:b]

def apply():
    source = APP.read_text(encoding="utf-8")
    source = once(source, SNAPSHOT_OLD, SNAPSHOT_NEW, "custody snapshot")
    source = once(source, LOG_OLD, LOG_NEW, "custody log")
    source = once(source, HELPER_OLD, "", "inline custody helper")
    APP.write_text(source, encoding="utf-8")

def verify():
    source = APP.read_text(encoding="utf-8")
    scoped = receiver(source)
    ordered = [
        "let leasedAccountUID = membershipAccountUID?.trimmingCharacters",
        "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: leasedAccountUID",
        "try await sessionLedger.recordApplicationUpdate",
        "await refreshLedgerSnapshot()",
        "guard currentConnectionToken == token,",
        "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == leasedAccountUID",
        "log(\"tuya_application_update\", custodySafeEventDetails)",
    ]
    offsets = [scoped.index(token) for token in ordered]
    if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
        raise SystemExit("lossless custody / post-await authority ordering regressed")
    for forbidden in ("redactedApplicationEventDetails(", "eventDetails[\"generation\"] =", "update.merging(["):
        if forbidden in scoped:
            raise SystemExit(f"lossy custody remains: {forbidden}")
    # Keep the independently accepted current private-secret custody untouched.
    for token in (
        "private static var exactSecretValues: [String]",
        "NembraTuyaPrivateIdentity.appKey",
        "NembraTuyaPrivateIdentity.appSecret",
        "private static func redactedApplicationDescription(_ object: Any) -> String",
        "sdk_source_authority_changed_before_application_event_custody",
    ):
        if token not in source:
            raise SystemExit(f"1138 dependency missing: {token}")

if __name__ == "__main__":
    import sys
    apply() if sys.argv[1] == "apply" else verify()
