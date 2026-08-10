from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaCaptureSecretCustodyConvergenceSourceTests.swift"


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

        // Redact both keys and values. If redaction makes distinct SDK keys collide, retain every
        // value with a deterministic suffix rather than silently discarding application evidence.
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
    if "private static func redactVerifiedAccountUID(" in source:
        raise SystemExit("account UID custody already exists; refresh live product")

    marker = "    private func receivedApplicationUpdate(\n"
    source = one(source, marker, UID_HELPER + marker, "UID helper insertion")

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
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
""",
        """            log("tuya_application_update", custodySafeUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
""",
        "trusted event metadata and UID-safe custody",
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
        raise SystemExit("secret custody convergence regression missing")

    required = (
        "<redacted-account-uid>",
        "private static func redactVerifiedAccountUID(",
        "redactAccountUIDOccurrences(in: key, accountUID: accountUID)",
        "redactAccountUIDOccurrences(in: value, accountUID: accountUID)",
        "let verifiedAccountUID = membershipAccountUID",
        "let custodySafeUpdate = Self.redactVerifiedAccountUID(",
        'log("tuya_application_update", custodySafeUpdate.merging([',
        "]) { _, trusted in trusted })",
    )
    for token in required:
        if token not in source:
            raise SystemExit(f"required secret custody token missing: {token}")

    start = source.index("private func receivedApplicationUpdate(")
    end = source.index("private func startWatchdog", start)
    receipt = source[start:end]
    if 'log("tuya_application_update", update.merging([' in receipt:
        raise SystemExit("raw application update still enters immutable event custody")
    if "{ current, _ in current }" in receipt:
        raise SystemExit("untrusted application generation can still win metadata collision")

    driver_start = source.index("@MainActor\nprivate final class SmartLifeDriver")
    fragments_start = source.index("private static let secretKeyFragments = [", driver_start)
    fragments_end = source.index("private static func redactApplicationSecrets", fragments_start)
    fragments = source[fragments_start:fragments_end]
    if fragments.count('"sessionkey"') != 1:
        raise SystemExit("sessionkey classifier remains duplicated")
    if '"uid"' in fragments:
        raise SystemExit("generic uid key was incorrectly blanket-redacted")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
