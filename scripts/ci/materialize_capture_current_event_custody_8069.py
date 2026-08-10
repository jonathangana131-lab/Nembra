from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PARENT = "8069c0ffec496cacbe263016d8a7f4ca15ddc64e"

EVENT_OLD = """            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n"""
EVENT_NEW = """            let eventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n                applicationUpdate: update,\n                trustedGeneration: String(token.diagnosticGeneration),\n                accountUID: membershipAccountUID\n            )\n            log(\"tuya_application_update\", eventDetails)\n"""
DUPLICATE_CLASSIFIER = """        \"refreshtoken\",\n        \"sessionkey\",\n        \"authkey\",\n"""
DEDUPLICATED_CLASSIFIER = """        \"refreshtoken\",\n        \"authkey\",\n"""


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: exact replacement target count was {count}, expected 1")
    return source.replace(old, new, 1)


def section(source: str, start: str, end: str) -> str:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return source[first:last]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    source = replace_once(source, EVENT_OLD, EVENT_NEW, "event custody")
    source = replace_once(source, DUPLICATE_CLASSIFIER, DEDUPLICATED_CLASSIFIER, "session-key classifier dedupe")
    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    receiver = section(source, "    private func receivedApplicationUpdate(", "    private func startWatchdog")
    for token in (
        "TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "applicationUpdate: update",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: membershipAccountUID",
        "log(\"tuya_application_update\", eventDetails)",
    ):
        if token not in receiver:
            raise SystemExit(f"event custody wiring missing: {token}")
    if "log(\"tuya_application_update\", update" in receiver:
        raise SystemExit("raw SDK application dictionary still enters event logging directly")

    driver = section(source, "private final class SmartLifeDriver", "#endif\n\nprivate enum AppleAccountAuthorizationError")
    classifier = section(driver, "    private static let secretKeyFragments = [", "]\n\n    private static func redactApplicationSecrets")
    if classifier.count('"sessionkey"') != 1:
        raise SystemExit("session-key classifier is not deduplicated")
    if '"uid"' in classifier:
        raise SystemExit("generic uid key was incorrectly blanket-redacted")

    primitive = (ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedApplicationEventCustody.swift").read_text(encoding="utf-8")
    for token in (
        "accountUIDRedactionMarker = \"<redacted-account-uid>\"",
        "output[trustedGenerationKey] = trustedGeneration",
        "for key in applicationUpdate.keys.sorted()",
    ):
        if token not in primitive:
            raise SystemExit(f"custody primitive contract missing: {token}")

    # The current 8069 foreground/status hardening is an accepted dependency of this reanchor.
    for token in (
        "guard phase != .accepted else { return }",
        "foreground_integrity_lost_after_target_correlation",
        "membershipStatus = \"Exact scooter membership must be verified again after Capture leaves Secure Link authority.\"",
    ):
        if token not in source:
            raise SystemExit(f"8069 dependency missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
