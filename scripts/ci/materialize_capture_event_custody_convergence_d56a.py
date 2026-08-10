from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PARENT = "d56a30c699fbdecec6130537d3f3f4f4232f5c47"

SNAPSHOT_OLD = """        let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)\n"""
SNAPSHOT_NEW = """        let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n            applicationUpdate: update,\n            trustedGeneration: String(token.diagnosticGeneration),\n            accountUID: leasedAccountUID\n        )\n"""
LOG_OLD = """            var eventDetails = custodySafeUpdate\n            eventDetails[\"generation\"] = String(token.diagnosticGeneration)\n            log(\"tuya_application_update\", eventDetails)\n"""
LOG_NEW = """            log(\"tuya_application_update\", custodySafeEventDetails)\n"""
HELPER_OLD = '''\n    private func redactedApplicationEventDetails(\n        _ update: [String: String],\n        accountUID: String\n    ) -> [String: String] {\n        var redacted: [String: String] = [:]\n        redacted.reserveCapacity(update.count)\n        for (key, value) in update.sorted(by: { $0.key < $1.key }) {\n            let redactedKey = key.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n            let redactedValue = value.replacingOccurrences(\n                of: accountUID,\n                with: "<redacted-account-uid>",\n                options: [.caseInsensitive, .literal]\n            )\n\n            // Redacting malformed keys can collapse two distinct SDK entries onto one key.\n            // Preserve every admitted opaque value under a deterministic redaction-safe suffix.\n            var custodyKey = redactedKey\n            var collisionOrdinal = 2\n            while redacted[custodyKey] != nil {\n                custodyKey = "\\(redactedKey)#\\(collisionOrdinal)"\n                collisionOrdinal += 1\n            }\n            redacted[custodyKey] = redactedValue\n        }\n        return redacted\n    }\n'''

DRIVER_CALLBACK_OLD = '''            } else {\n                sanitized[keyString] = String(describing: Self.redactApplicationSecrets(value))\n            }\n'''
DRIVER_CALLBACK_NEW = '''            } else {\n                let recursivelySanitizedValue = Self.redactApplicationSecrets(value)\n                sanitized[keyString] = Self.redactKnownSecretValues(\n                    in: String(describing: recursivelySanitizedValue)\n                )\n            }\n'''

DRIVER_SANITIZER_MARKER = '''    private static func redactApplicationSecrets(_ object: Any) -> Any {\n'''
DRIVER_SANITIZER_PREFIX = '''    private static var exactSecretValues: [String] {\n#if canImport(NembraTuyaPrivateConfig)\n        [\n            NembraTuyaPrivateIdentity.appKey,\n            NembraTuyaPrivateIdentity.appSecret,\n        ]\n        .filter { !$0.isEmpty }\n        .sorted { $0.utf8.count > $1.utf8.count }\n#else\n        []\n#endif\n    }\n\n    private static func redactKnownSecretValues(in value: String) -> String {\n        var redacted = value\n        for secret in exactSecretValues {\n            redacted = redacted.replacingOccurrences(\n                of: secret,\n                with: "<redacted>",\n                options: [.literal]\n            )\n        }\n        return redacted\n    }\n\n    private static func redactApplicationSecrets(_ object: Any) -> Any {\n'''

STRING_LEAF_OLD = '''        if let array = object as? [Any] {\n            return array.map(redactApplicationSecrets)\n        }\n        return object\n'''
STRING_LEAF_NEW = '''        if let array = object as? [Any] {\n            return array.map(redactApplicationSecrets)\n        }\n        if let string = object as? String {\n            return redactKnownSecretValues(in: string)\n        }\n        return object\n'''


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def section(source: str, start: str, end: str) -> str:
    a = source.index(start)
    b = source.index(end, a + len(start))
    return source[a:b]


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    source = replace_once(source, SNAPSHOT_OLD, SNAPSHOT_NEW, "admission-time event custody")
    source = replace_once(source, LOG_OLD, LOG_NEW, "immutable event log")
    source = replace_once(source, HELPER_OLD, "", "inline account redactor")
    source = replace_once(source, DRIVER_CALLBACK_OLD, DRIVER_CALLBACK_NEW, "driver callback value custody")
    source = replace_once(source, DRIVER_SANITIZER_MARKER, DRIVER_SANITIZER_PREFIX, "driver exact-secret helpers")
    source = replace_once(source, STRING_LEAF_OLD, STRING_LEAF_NEW, "recursive string secret scrub")
    APP.write_text(source, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    receiver = section(source, "    private func receivedApplicationUpdate(", "    private func startWatchdog")
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
    offsets = [receiver.index(token) for token in ordered]
    if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
        raise SystemExit("application event custody / post-await authority order regressed")
    for forbidden in (
        "redactedApplicationEventDetails(",
        "eventDetails[\"generation\"] =",
        "var eventDetails = custodySafeUpdate",
        "update.merging([",
    ):
        if forbidden in receiver:
            raise SystemExit(f"lossy downstream custody remains: {forbidden}")

    driver = section(
        source,
        "@MainActor\nprivate final class SmartLifeDriver",
        "#endif\n\nprivate enum AppleAccountAuthorizationError",
    )
    for required in (
        "NembraTuyaPrivateIdentity.appKey",
        "NembraTuyaPrivateIdentity.appSecret",
        "private static var exactSecretValues: [String]",
        "private static func redactKnownSecretValues(in value: String)",
        "replacingOccurrences(",
        "let recursivelySanitizedValue = Self.redactApplicationSecrets(value)",
        "String(describing: recursivelySanitizedValue)",
        "return redactKnownSecretValues(in: string)",
    ):
        if required not in driver:
            raise SystemExit(f"driver exact-secret custody missing: {required}")
    if "String(describing: Self.redactApplicationSecrets(value))" in driver:
        raise SystemExit("driver still stringifies key-only sanitizer directly")

    for current_guard in (
        "sdk_source_authority_changed_before_application_event_custody",
        "applicationUpdateAdmissionsInFlight += 1",
        "accountIdentityLeaseIsAuthorized",
        "foreground_integrity_lost_after_target_correlation",
    ):
        if current_guard not in source:
            raise SystemExit(f"current product guard missing: {current_guard}")

    primitive = (ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedApplicationEventCustody.swift").read_text(encoding="utf-8")
    for required in (
        "applicationUpdate.keys.sorted()",
        "occupiedKeys: Set<String> = [trustedGenerationKey]",
        "while occupiedKeys.contains(admittedKey)",
        "admittedKey = \"application.\\(admittedKey)\"",
        "output[trustedGenerationKey] = trustedGeneration",
        "options: [.caseInsensitive, .literal]",
    ):
        if required not in primitive:
            raise SystemExit(f"package event custody missing: {required}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
