from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
UID_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDExportCustodySourceTests.swift")
PROVENANCE_TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationEventMetadataPrecedenceSourceTests.swift")

UID_TEST_SOURCE = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted application evidence redacts the verified account UID before event custody")
    func applicationEvidenceCannotExportVerifiedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let updateAdmission = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let prepareExport = String(try section(
            in: source,
            from: "func prepareExport()",
            to: "private func abandonPackageCorrelation()"
        ))

        #expect(prepareExport.contains("No account UID"))
        #expect(updateAdmission.contains("membershipAccountUID"))
        #expect(updateAdmission.contains("<redacted-account-uid>"))
        #expect(updateAdmission.contains("redactedApplicationEventDetails(update)"))
        #expect(!updateAdmission.contains("log(\"tuya_application_update\", update"))
    }

    @Test("account UID custody is value-bound rather than a blanket generic uid-key rule")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))
        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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

PROVENANCE_TEST_SOURCE = r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event metadata precedence")
struct TuyaApplicationEventMetadataPrecedenceSourceTests {
    @Test("SDK application keys cannot overwrite Nembra generation provenance")
    func trustedGenerationWinsReservedKeyCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("var eventDetails = redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        #expect(receiver.contains("log(\"tuya_application_update\", eventDetails)"))
        #expect(!receiver.contains("update.merging(["))
        let details = try #require(receiver.range(of: "var eventDetails = redactedApplicationEventDetails(update)"))
        let trusted = try #require(receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(details.lowerBound < trusted.lowerBound)
        #expect(trusted.lowerBound < log.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
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


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old_log = '''            log("tuya_application_update", update.merging([
                "generation": String(token.diagnosticGeneration)
            ]) { current, _ in current })
'''
    new_log = '''            var eventDetails = redactedApplicationEventDetails(update)
            eventDetails["generation"] = String(token.diagnosticGeneration)
            log("tuya_application_update", eventDetails)
'''
    source = replace_once(source, old_log, new_log, "trusted application event metadata")

    marker = "\n    private func startWatchdog(token: TuyaReadOnlyConnectionToken) {"
    helper = r'''
    private func redactedApplicationEventDetails(_ update: [String: String]) -> [String: String] {
        guard let accountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accountUID.isEmpty else {
            return update
        }
        return update.mapValues { value in
            value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.literal]
            )
        }
    }
'''
    source = replace_once(source, marker, helper + marker, "account UID event redactor")
    APP.write_text(source, encoding="utf-8")

    if UID_TEST.exists() or PROVENANCE_TEST.exists():
        raise SystemExit("expected red source tests to be absent on product parent")
    UID_TEST.write_text(UID_TEST_SOURCE, encoding="utf-8")
    PROVENANCE_TEST.write_text(PROVENANCE_TEST_SOURCE, encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    start = source.index("private func receivedApplicationUpdate(")
    end = source.index("private func startWatchdog", start)
    section = source[start:end]
    required = (
        "var eventDetails = redactedApplicationEventDetails(update)",
        'eventDetails["generation"] = String(token.diagnosticGeneration)',
        'log("tuya_application_update", eventDetails)',
        "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
        'with: "<redacted-account-uid>"',
    )
    for token in required:
        if token not in section:
            raise SystemExit(f"application event custody token missing: {token}")
    if "update.merging([" in section or 'log("tuya_application_update", update' in section:
        raise SystemExit("raw/untrusted-first application event log survived")
    if section.index("redactedApplicationEventDetails(update)") >= section.index('eventDetails["generation"]'):
        raise SystemExit("value redaction must precede trusted provenance stamping")
    if section.index('eventDetails["generation"]') >= section.index('log("tuya_application_update", eventDetails)'):
        raise SystemExit("trusted provenance stamping must precede accepted event log")
    for path, marker in (
        (UID_TEST, "applicationEvidenceCannotExportVerifiedAccountUID"),
        (PROVENANCE_TEST, "trustedGenerationWinsReservedKeyCollision"),
    ):
        text = path.read_text(encoding="utf-8")
        if marker not in text:
            raise SystemExit(f"regression missing: {marker}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("apply", "verify"))
    args = parser.parse_args()
    apply() if args.mode == "apply" else verify()
