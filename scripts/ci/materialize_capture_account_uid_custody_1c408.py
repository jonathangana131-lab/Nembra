from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureRedTeamConvergenceSourceTests.swift"


def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def replace_in_section(source: str, start_token: str, end_token: str, old: str, new: str, label: str) -> str:
    start = source.index(start_token)
    end = source.index(end_token, start)
    prefix, section, suffix = source[:start], source[start:end], source[end:]
    section = one(section, old, new, label)
    return prefix + section + suffix


UID_HELPER = '''    private static func redactAccountUIDOccurrences(in text: String, accountUID: String) -> String {
        guard !accountUID.isEmpty else { return text }
        return text.replacingOccurrences(
            of: accountUID,
            with: "<redacted-account-uid>",
            options: [.literal]
        )
    }

    private static func redactVerifiedAccountUID(
        in update: [String: String],
        accountUID: String
    ) -> [String: String] {
        guard !accountUID.isEmpty else { return update }
        var sanitized: [String: String] = [:]

        // Redact both keys and values. If redaction makes two distinct SDK keys collide, retain
        // every value with a deterministic suffix instead of dropping application evidence.
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = redactAccountUIDOccurrences(in: key, accountUID: accountUID)
            var custodyKey = redactedKey
            var collisionIndex = 2
            while sanitized[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionIndex)"
                collisionIndex += 1
            }
            sanitized[custodyKey] = redactAccountUIDOccurrences(in: value, accountUID: accountUID)
        }
        return sanitized
    }

'''


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")

    marker = "    private func receivedApplicationUpdate(\n"
    if source.count(marker) != 1:
        raise SystemExit(f"application update marker changed: {source.count(marker)}")
    if "private static func redactVerifiedAccountUID(" in source:
        raise SystemExit("account UID custody helper already exists; refresh live product")
    source = source.replace(marker, UID_HELPER + marker, 1)

    source = replace_in_section(
        source,
        "private func receivedApplicationUpdate(",
        "private func startWatchdog",
        """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
""",
        """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID,
              !verifiedAccountUID.isEmpty,
              let driver else {
""",
        "verified account UID admission snapshot",
    )

    source = replace_in_section(
        source,
        "private func receivedApplicationUpdate(",
        "private func startWatchdog",
        """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
""",
        """        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        let custodySafeUpdate = Self.redactVerifiedAccountUID(
            in: update,
            accountUID: verifiedAccountUID
        )
        applicationUpdateAdmissionsInFlight += 1
""",
        "account UID custody projection",
    )

    source = replace_in_section(
        source,
        "private func receivedApplicationUpdate(",
        "private func startWatchdog",
        """            log("tuya_application_update", update.merging([
""",
        """            log("tuya_application_update", custodySafeUpdate.merging([
""",
        "event custody uses scrubbed application update",
    )

    source = one(
        source,
        '        "refreshtoken",\n        "sessionkey",\n',
        '        "refreshtoken",\n',
        "duplicate sessionkey secret fragment",
    )

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if not TEST.exists():
        raise SystemExit("convergence regression missing")

    for token in (
        "<redacted-account-uid>",
        "private static func redactVerifiedAccountUID(",
        "redactAccountUIDOccurrences(in: key, accountUID: accountUID)",
        "redactAccountUIDOccurrences(in: value, accountUID: accountUID)",
        "let verifiedAccountUID = membershipAccountUID",
        "let custodySafeUpdate = Self.redactVerifiedAccountUID(",
        'log("tuya_application_update", custodySafeUpdate.merging([',
        "]) { _, trusted in trusted })",
    ):
        if token not in source:
            raise SystemExit(f"required account UID custody token missing: {token}")

    receipt_start = source.index("private func receivedApplicationUpdate(")
    receipt_end = source.index("private func startWatchdog", receipt_start)
    receipt = source[receipt_start:receipt_end]
    if 'log("tuya_application_update", update.merging([' in receipt:
        raise SystemExit("raw application update still enters event custody")

    driver_start = source.index("@MainActor\nprivate final class SmartLifeDriver")
    fragments_start = source.index("private static let secretKeyFragments = [", driver_start)
    fragments_end = source.index("private static func redactApplicationSecrets", fragments_start)
    fragments = source[fragments_start:fragments_end]
    if fragments.count('"sessionkey"') != 1:
        raise SystemExit("sessionkey secret fragment is not deduplicated")
    if '"uid"' in fragments:
        raise SystemExit("generic uid key must not be blanket-redacted")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
