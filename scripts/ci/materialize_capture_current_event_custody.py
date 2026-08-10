from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
PARENT = "1c40853f6991b4d09206df1d25ecff021458b7eb"
STATUS = "Exact scooter membership must be verified again for this Secure Link session."


def section_bounds(source: str, start: str, end: str) -> tuple[int, int]:
    first = source.index(start)
    last = source.index(end, first + len(start))
    return first, last


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: replacement target count was {count}, expected 1")
    return source.replace(old, new, 1)


def replace_once_in_section(source: str, start: str, end: str, old: str, new: str, label: str) -> str:
    first, last = section_bounds(source, start, end)
    scoped = source[first:last]
    replaced = replace_once(scoped, old, new, label)
    return source[:first] + replaced + source[last:]


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")

    status_old = """        sdkDeviceMembershipVerified = false\n        membershipAccountUID = nil\n"""
    status_new = f"""        sdkDeviceMembershipVerified = false\n        membershipStatus = \"{STATUS}\"\n        membershipAccountUID = nil\n"""
    source = replace_once_in_section(
        source,
        "    func abandonCorrelationForViewExit() {",
        "    func appDidLoseForeground() {",
        status_old,
        status_new,
        "view-exit membership status",
    )
    source = replace_once_in_section(
        source,
        "    func appDidLoseForeground() {",
        "    var privateConfig: Bool",
        status_old,
        status_new,
        "foreground membership status",
    )

    event_old = """            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n"""
    event_new = """            let eventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails(\n                applicationUpdate: update,\n                trustedGeneration: String(token.diagnosticGeneration),\n                accountUID: membershipAccountUID\n            )\n            log(\"tuya_application_update\", eventDetails)\n"""
    source = replace_once(source, event_old, event_new, "authenticated application event custody")

    duplicate_classifier = """        \"refreshtoken\",\n        \"sessionkey\",\n        \"authkey\",\n"""
    deduplicated_classifier = """        \"refreshtoken\",\n        \"authkey\",\n"""
    source = replace_once(source, duplicate_classifier, deduplicated_classifier, "duplicate session-key classifier")

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    view_exit_start, view_exit_end = section_bounds(
        source,
        "    func abandonCorrelationForViewExit() {",
        "    func appDidLoseForeground() {",
    )
    foreground_start, foreground_end = section_bounds(
        source,
        "    func appDidLoseForeground() {",
        "    var privateConfig: Bool",
    )
    receiver_start, receiver_end = section_bounds(
        source,
        "    private func receivedApplicationUpdate(",
        "    private func startWatchdog",
    )
    driver_start, driver_end = section_bounds(
        source,
        "private final class SmartLifeDriver",
        "#endif\n\nprivate enum AppleAccountAuthorizationError",
    )

    for label, cleanup in (
        ("view-exit", source[view_exit_start:view_exit_end]),
        ("foreground", source[foreground_start:foreground_end]),
    ):
        ordered = [
            "sdkDeviceMembershipVerified = false",
            f"membershipStatus = \"{STATUS}\"",
            "membershipRequestID = UUID()",
        ]
        offsets = [cleanup.index(token) for token in ordered]
        if offsets != sorted(offsets) or len(set(offsets)) != len(offsets):
            raise SystemExit(f"{label}: membership status revocation ordering is not fail-closed")
        if "membershipStatus = \"Exact scooter membership verified and leased to this current SDK account.\"" in cleanup:
            raise SystemExit(f"{label}: retained positive membership authority copy")

    receiver = source[receiver_start:receiver_end]
    required_receiver = [
        "TuyaAuthenticatedApplicationEventCustody.eventDetails(",
        "applicationUpdate: update",
        "trustedGeneration: String(token.diagnosticGeneration)",
        "accountUID: membershipAccountUID",
        "log(\"tuya_application_update\", eventDetails)",
    ]
    for token in required_receiver:
        if token not in receiver:
            raise SystemExit(f"event custody wiring missing: {token}")
    if "log(\"tuya_application_update\", update" in receiver:
        raise SystemExit("raw SDK application dictionary still enters event custody directly")

    driver = source[driver_start:driver_end]
    classifier_start, classifier_end = section_bounds(
        driver,
        "    private static let secretKeyFragments = [",
        "]\n\n    private static func redactApplicationSecrets",
    )
    classifier = driver[classifier_start:classifier_end]
    if classifier.count('"sessionkey"') != 1:
        raise SystemExit("session-key secret classifier is not deduplicated")
    if '"uid"' in classifier:
        raise SystemExit("generic uid key was incorrectly promoted to blanket secret classification")

    primitive = ROOT / "Packages/NembraBluetoothCapture/Sources/NembraBluetoothCapture/TuyaAuthenticatedApplicationEventCustody.swift"
    if not primitive.exists():
        raise SystemExit("event custody primitive missing")
    primitive_source = primitive.read_text(encoding="utf-8")
    for token in (
        "accountUIDRedactionMarker = \"<redacted-account-uid>\"",
        "output[trustedGenerationKey] = trustedGeneration",
        "for key in applicationUpdate.keys.sorted()",
    ):
        if token not in primitive_source:
            raise SystemExit(f"event custody primitive contract missing: {token}")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
