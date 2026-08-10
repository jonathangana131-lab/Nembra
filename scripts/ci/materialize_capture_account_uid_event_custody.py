from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENTRYPOINT = ROOT / "NembraApp/App/NembraCaptureEntrypoint.swift"
TEST = ROOT / "Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift"

RECEIVER_START = "    private func receivedApplicationUpdate(\n"
HELPER = '''    private func redactVerifiedAccountUIDFromApplicationEvent(
        _ update: [String: String],
        verifiedAccountUID: String
    ) -> [String: String] {
        let accountUID = verifiedAccountUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountUID.isEmpty else { return [:] }
        func redact(_ value: String) -> String {
            value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
        }
        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            redacted[redact(key)] = redact(value)
        }
        return redacted
    }

'''
DRIVER_GUARD = '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }

        applicationUpdateAdmissionsInFlight += 1
'''
DRIVER_GUARD_REDACT = '''        guard driver.isLocallyConnected(uuid: tuyaUUID) else {
            await recordObservedTransportLoss(token: token)
            return
        }
        guard let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !verifiedAccountUID.isEmpty else {
            await invalidateSourceAuthority(
                token: token,
                message: "Verified Tuya account identity became unavailable before application evidence custody.",
                kind: "sdk_account_uid_authority_missing_during_observation"
            )
            return
        }
        let redactedUpdate = redactVerifiedAccountUIDFromApplicationEvent(
            update,
            verifiedAccountUID: verifiedAccountUID
        )

        applicationUpdateAdmissionsInFlight += 1
'''
RAW_LOG = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
'''
SAFE_LOG = '''            log("tuya_application_update", redactedUpdate.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { _, trusted in trusted })
'''

TEST_CONTENT = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence redacts verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let helper = String(try section(in: source, from: "private func redactVerifiedAccountUIDFromApplicationEvent(", to: "private func receivedApplicationUpdate("))
        let export = String(try section(in: source, from: "func prepareExport()", to: "private func abandonPackageCorrelation()"))

        #expect(export.contains("No account UID"))
        #expect(source.contains("<redacted-account-uid>"))
        #expect(receiver.contains("let verifiedAccountUID = membershipAccountUID"))
        #expect(receiver.contains("let redactedUpdate = redactVerifiedAccountUIDFromApplicationEvent("))
        #expect(receiver.contains("log(\"tuya_application_update\", redactedUpdate.merging(["))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
        #expect(helper.contains("replacingOccurrences"))
        #expect(helper.contains("options: [.caseInsensitive, .literal]"))
        #expect(helper.contains("redacted[redact(key)] = redact(value)"))
    }

    @Test("account UID custody is value-bound rather than blanket generic uid-key classification")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(in: source, from: "@MainActor\nprivate final class SmartLifeDriver", to: "#endif\n\nprivate enum AppleAccountAuthorizationError"))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
'''


def apply() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    if "private func redactVerifiedAccountUIDFromApplicationEvent(" in source:
        raise SystemExit("account-UID event sanitizer already exists")
    if source.count(RECEIVER_START) != 1 or source.count(DRIVER_GUARD) != 1 or source.count(RAW_LOG) != 1:
        raise SystemExit("account-UID custody source anchors changed")
    source = source.replace(RECEIVER_START, HELPER + RECEIVER_START, 1)
    source = source.replace(DRIVER_GUARD, DRIVER_GUARD_REDACT, 1)
    source = source.replace(RAW_LOG, SAFE_LOG, 1)
    ENTRYPOINT.write_text(source, encoding="utf-8")
    if TEST.exists():
        raise SystemExit("account-UID custody regression already exists")
    TEST.write_text(TEST_CONTENT, encoding="utf-8")


def verify() -> None:
    source = ENTRYPOINT.read_text(encoding="utf-8")
    for token in (
        "private func redactVerifiedAccountUIDFromApplicationEvent(",
        "<redacted-account-uid>",
        "let verifiedAccountUID = membershipAccountUID",
        "redacted[redact(key)] = redact(value)",
        'log("tuya_application_update", redactedUpdate.merging([',
    ):
        if token not in source:
            raise SystemExit(f"account-UID custody token missing: {token}")
    if 'log("tuya_application_update", update.merging([' in source:
        raise SystemExit("raw application update still enters event custody")
    if not TEST.exists():
        raise SystemExit("account-UID custody regression missing")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
