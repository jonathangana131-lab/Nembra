from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PARENT = "29000f240d1b5710bbe116de94a22c030d10da8e"

SNAPSHOT_OLD = """        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n"""
SNAPSHOT_NEW = """        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n"""
LOG_OLD = """            var eventDetails = custodySafeUpdate\n            eventDetails[\"generation\"] = String(token.diagnosticGeneration)\n            log(\"tuya_application_update\", eventDetails)\n"""
LOG_NEW = """            log(\"tuya_application_update\", custodySafeEventDetails)\n"""
HELPER_OLD = '''\n    private func redactedApplicationEventDetails(\n        _ update: [String: String],\n        accountUID: String\n    ) -> [String: String] {\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update.sorted(by: { $0.key < $1.key }) {\n            let redactedKey = key.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n            let redactedValue = value.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n\n            // Redacting malformed keys can collapse two distinct SDK entries onto one key.\n            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.\n            var custodyKey = redactedKey\n            var collisionOrdinal = 2\n            while redacted[custodyKey] != nil {\n                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"\n                collisionOrdinal += 1\n            }\n            redacted[custodyKey] = redactedValue\n        }\n        return redacted\n    }\n'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def receiver(source: str) -> str:
    start = source.index("    private func receivedApplicationUpdate(")
    end = source.index("    private func startWatchdog", start)
    return source[start:end]


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    source = replace_once(source, SNAPSHOT_OLD, SNAPSHOT_NEW, "pre-suspension custody snapshot")
    source = replace_once(source, LOG_OLD, LOG_NEW, "immutable event admission")
    source = replace_once(source, HELPER_OLD, "", "inline lossy helper")
    APP.write_text(source, encoding="utf-8")


def verify() -> None:
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
    offsets = []
    for token in ordered:
        if token not in scoped:
            raise SystemExit(f"receiver missing exact-current invariant: {token}")
        offsets.append(scoped.index(token))
    if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
        raise SystemExit("event custody / post-await authority ordering regressed")

    for forbidden in (
        "redactedApplicationEventDetails(",
        "eventDetails[\"generation\"] =",
        "var eventDetails = custodySafeUpdate",
        "update.merging([",
        "log(\"tuya_application_update\", update",
    ):
        if forbidden in scoped:
            raise SystemExit(f"lossy event custody path remains: {forbidden}")

    for current_guard in (
        "sdk_source_authority_changed_before_application_event_custody",
        "applicationUpdateAdmissionsInFlight += 1",
        "accountIdentityLeaseIsAuthorized",
        "guard phase != .accepted else { return }",
        "foreground_integrity_lost_after_target_correlation",
    ):
        if current_guard not in source:
            raise SystemExit(f"current product guard missing: {current_guard}")

    primitive = (ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedApplicationEventCustody.swift").read_text(encoding="utf-8")
    for token in (
        "applicationUpdate.keys.sorted()",
        "occupiedKeys: Set<String> = [trustedGenerationKey]",
        "while occupiedKeys.contains(admittedKey)",
        "admittedKey = \"application.\\(admittedKey)\"",
        "output[trustedGenerationKey] = trustedGeneration",
        "options: [.caseInsensitive, .literal]",
    ):
        if token not in primitive:
            raise SystemExit(f"package custody contract missing: {token}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
