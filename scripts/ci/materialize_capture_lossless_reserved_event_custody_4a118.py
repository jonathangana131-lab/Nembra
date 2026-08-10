from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PARENT = "4a11865c4b16b778aa03634e7ca3bdbc50b0432e"

CUSTODY_OLD = '''        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            var eventDetails = custodySafeUpdate\n            eventDetails["generation"] = String(token.diagnosticGeneration)\n            log("tuya_application_update", eventDetails)\n'''

CUSTODY_NEW = '''        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n\n        do {\n            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log("tuya_application_update", custodySafeEventDetails)\n'''

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
    source = replace_once(source, CUSTODY_OLD, CUSTODY_NEW, "event custody caller")
    source = replace_once(source, HELPER_OLD, "", "inline event custody helper")
    APP.write_text(source, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    scoped = receiver(source)

    required = (
        "let leasedAccountUID = membershipAccountUID?.trimmingCharacters",
        "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "applicationUpdate: update",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: leasedAccountUID",
        "try await sessionLedger.recordApplicationUpdate",
        "log(\"tuya_application_update\", custodySafeEventDetails)",
    )
    positions = []
    for token in required:
        if token not in scoped:
            raise SystemExit(f"receiver missing required custody token: {token}")
        positions.append(scoped.index(token))

    # Admission snapshot and complete custody record must be frozen before the first actor hop.
    lease = scoped.index("let leasedAccountUID = membershipAccountUID?.trimmingCharacters")
    custody = scoped.index("let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(")
    account = scoped.index("accountUID: leasedAccountUID")
    first_await = scoped.index("try await sessionLedger.recordApplicationUpdate")
    log = scoped.index("log(\"tuya_application_update\", custodySafeEventDetails)")
    if not (lease < custody < account < first_await < log):
        raise SystemExit("admission-time account/provenance custody ordering regressed")

    post_await = scoped[first_await:]
    if "membershipAccountUID" in post_await:
        raise SystemExit("post-suspension event path rereads mutable account identity")

    forbidden = (
        "redactedApplicationEventDetails(",
        "eventDetails[\"generation\"] =",
        "update.merging([",
        "log(\"tuya_application_update\", update",
    )
    for token in forbidden:
        if token in scoped:
            raise SystemExit(f"lossy event custody path remains: {token}")

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
            raise SystemExit(f"package custody primitive missing contract: {token}")

    # Preserve exact-current account-race and foreground truth from the parent.
    for token in (
        "applicationUpdateAdmissionsInFlight += 1",
        "guard phase != .accepted else { return }",
        "foreground_integrity_lost_after_target_correlation",
    ):
        if token not in source:
            raise SystemExit(f"exact-current parent dependency missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
