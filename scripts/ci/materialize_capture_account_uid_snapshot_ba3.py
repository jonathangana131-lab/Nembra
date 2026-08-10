from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift"


def one(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return source.replace(old, new, 1)


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")

    source = one(
        source,
        """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let driver else {
""",
        """        guard sdkAccountLoggedIn,
              sdkDeviceMembershipVerified,
              accountIdentityLeaseIsAuthorized,
              let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty,
              let driver else {
""",
        "account UID admission snapshot",
    )

    source = one(
        source,
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

        // Bind redaction to the same account lease that admitted this callback before any await
        // can permit a MainActor account transition to clear or replace that lease.
        let custodySafeUpdate = Self.redactedApplicationEventDetails(
            update,
            accountUID: verifiedAccountUID
        )
        applicationUpdateAdmissionsInFlight += 1
""",
        "pre-suspension UID custody projection",
    )

    source = one(
        source,
        """            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
""",
        """            var eventDetails = custodySafeUpdate
            eventDetails["generation"] = String(token.diagnosticGeneration)
""",
        "event custody projection",
    )

    source = one(
        source,
        """    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return update
        }

        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            redacted[redactedKey] = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
    }
""",
        """    private static func redactedApplicationEventDetails(
        _ update: [String: String],
        accountUID: String
    ) -> [String: String] {
        guard !accountUID.isEmpty else { return update }

        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update.sorted(by: { $0.key < $1.key }) {
            let redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            var custodyKey = redactedKey
            var collisionIndex = 2
            while redacted[custodyKey] != nil {
                custodyKey = "\\(redactedKey)#\\(collisionIndex)"
                collisionIndex += 1
            }
            redacted[custodyKey] = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        return redacted
    }
""",
        "lease-parameterized collision-preserving scrubber",
    )

    ENTRYPOINT.write_text(source, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if not TEST.exists():
        raise SystemExit("UID custody regression missing")

    start = source.index("private func receivedApplicationUpdate(")
    end = source.index("private func startWatchdog", start)
    receipt = source[start:end]

    required = (
        "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
        "!verifiedAccountUID.isEmpty",
        "let custodySafeUpdate = Self.redactedApplicationEventDetails(",
        "accountUID: verifiedAccountUID",
        "var eventDetails = custodySafeUpdate",
        'eventDetails["generation"] = String(token.diagnosticGeneration)',
        "private static func redactedApplicationEventDetails(",
        "accountUID: String",
        "update.sorted(by: { $0.key < $1.key })",
        "while redacted[custodyKey] != nil",
        'custodyKey = "\\(redactedKey)#\\(collisionIndex)"',
    )
    for token in required:
        if token not in receipt:
            raise SystemExit(f"required UID custody token missing: {token}")

    snapshot = receipt.index("let verifiedAccountUID = membershipAccountUID?.trimmingCharacters")
    projection = receipt.index("let custodySafeUpdate = Self.redactedApplicationEventDetails(")
    first_await = receipt.index("try await sessionLedger.recordApplicationUpdate")
    if not snapshot < projection < first_await:
        raise SystemExit("UID lease snapshot/projection must complete before first suspension point")

    helper_start = receipt.index("private static func redactedApplicationEventDetails(")
    helper = receipt[helper_start:]
    if "membershipAccountUID" in helper:
        raise SystemExit("UID scrubber must not re-read mutable membership lease")
    if 'log("tuya_application_update", update' in receipt:
        raise SystemExit("raw application update still enters event custody")


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
