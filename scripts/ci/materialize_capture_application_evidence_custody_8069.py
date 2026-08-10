from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
SOURCE_TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEvidenceCustodySourceTests.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, got {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text()

    source = replace_once(
        source,
        """    private func receivedApplicationUpdate(\n        _ update: [String: String],\n        token: TuyaReadOnlyConnectionToken\n    ) async {\n""",
        """    private static let redactedAccountUIDMarker = \"<redacted-account-uid>\"\n    private static let redactedAccountUIDKeyCollisionMarker = \"<redacted-account-uid-key-collision>\"\n\n    private static func redactVerifiedAccountUID(\n        from update: [String: String],\n        verifiedAccountUID: String\n    ) -> [String: String] {\n        guard !verifiedAccountUID.isEmpty else { return [:] }\n        var redacted: [String: String] = [:]\n        for (key, value) in update {\n            let safeKey = key.replacingOccurrences(\n                of: verifiedAccountUID,\n                with: redactedAccountUIDMarker\n            )\n            let safeValue = value.replacingOccurrences(\n                of: verifiedAccountUID,\n                with: redactedAccountUIDMarker\n            )\n            if redacted[safeKey] == nil {\n                redacted[safeKey] = safeValue\n            } else {\n                // Redacting a malformed UID-bearing key can collapse two distinct original keys.\n                // Preserve the fact that evidence collided without retaining either identity-bearing key.\n                redacted[safeKey] = redactedAccountUIDKeyCollisionMarker\n            }\n        }\n        return redacted\n    }\n\n    private func receivedApplicationUpdate(\n        _ update: [String: String],\n        token: TuyaReadOnlyConnectionToken\n    ) async {\n""",
        "insert account UID scrubber",
    )

    source = replace_once(
        source,
        """        guard sdkAccountLoggedIn,\n              sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              let driver else {\n""",
        """        guard sdkAccountLoggedIn,\n              sdkDeviceMembershipVerified,\n              accountIdentityLeaseIsAuthorized,\n              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),\n              !verifiedAccountUID.isEmpty,\n              let driver else {\n""",
        "bind application admission to verified account UID lease",
    )

    source = replace_once(
        source,
        """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n\n        applicationUpdateAdmissionsInFlight += 1\n""",
        """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {\n            await recordObservedTransportLoss(token: token)\n            return\n        }\n\n        let acceptedApplicationUpdate = Self.redactVerifiedAccountUID(\n            from: update,\n            verifiedAccountUID: verifiedAccountUID\n        )\n\n        applicationUpdateAdmissionsInFlight += 1\n""",
        "scrub application evidence before admission",
    )

    source = replace_once(
        source,
        """            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !update.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log(\"tuya_application_update\", update.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { current, _ in current })\n""",
        """            try await sessionLedger.recordApplicationUpdate(isNonEmpty: !acceptedApplicationUpdate.isEmpty, for: token)\n            await refreshLedgerSnapshot()\n            log(\"tuya_application_update\", acceptedApplicationUpdate.merging([\n                \"generation\": String(token.diagnosticGeneration)\n            ]) { _, trusted in trusted })\n""",
        "trusted event metadata precedence",
    )

    source = replace_once(
        source,
        """        \"refreshtoken\",\n        \"sessionkey\",\n        \"authkey\",\n""",
        """        \"refreshtoken\",\n        \"authkey\",\n""",
        "remove duplicate sessionkey classifier",
    )

    ENTRYPOINT.write_text(source)


def verify() -> None:
    source = ENTRYPOINT.read_text()
    test = SOURCE_TEST.read_text()
    receiver_start = source.index("    private func receivedApplicationUpdate(")
    receiver_end = source.index("    private func startWatchdog", receiver_start)
    receiver = source[receiver_start:receiver_end]
    scrubber_start = source.index("    private static let redactedAccountUIDMarker")
    scrubber = source[scrubber_start:receiver_start]

    required_receiver = [
        "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters",
        "Self.redactVerifiedAccountUID(",
        "verifiedAccountUID: verifiedAccountUID",
        "acceptedApplicationUpdate.merging([",
        ") { _, trusted in trusted })",
    ]
    for token in required_receiver:
        if token not in receiver:
            raise SystemExit(f"missing receiver invariant: {token}")
    if "update.merging([" in receiver or ") { current, _ in current })" in receiver:
        raise SystemExit("untrusted event metadata precedence remains")

    required_scrubber = [
        '"<redacted-account-uid>"',
        '"<redacted-account-uid-key-collision>"',
        "key.replacingOccurrences(",
        "value.replacingOccurrences(",
        "of: verifiedAccountUID",
        "redacted[safeKey] == nil",
        "redactedAccountUIDKeyCollisionMarker",
    ]
    for token in required_scrubber:
        if token not in scrubber:
            raise SystemExit(f"missing UID scrubber invariant: {token}")

    driver_start = source.index("@MainActor\nprivate final class SmartLifeDriver")
    driver_end = source.index("#endif\n\nprivate enum AppleAccountAuthorizationError", driver_start)
    driver = source[driver_start:driver_end]
    if driver.count('"sessionkey"') != 1:
        raise SystemExit("sessionkey classifier must be unique")
    if '"uid",' in driver or '"uid"\n' in driver:
        raise SystemExit("blanket uid classifier is forbidden")

    for token in [
        "verifiedAccountUID",
        "acceptedApplicationUpdate.merging([",
        "key.replacingOccurrences(",
        "value.replacingOccurrences(",
        "OfficialTuyaFactory.packageCorrelationMayStart",
    ]:
        if token not in source and token != "OfficialTuyaFactory.packageCorrelationMayStart":
            raise SystemExit(f"source invariant missing: {token}")
    if "accepted application evidence binds UID scrubbing" not in test:
        raise SystemExit("combined evidence custody source contract missing")


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"apply", "verify"}:
        raise SystemExit("usage: materialize_capture_application_evidence_custody_8069.py apply|verify")
    globals()[sys.argv[1]]()
