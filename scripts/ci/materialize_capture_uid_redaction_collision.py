from pathlib import Path

APP = Path("NembraApp/App/NembraCaptureEntrypoint.swift")
TEST = Path("Packages/NembraBluetoothCapture/Tests/NembraBluetoothCaptureTests/TuyaApplicationAccountUIDKeyCollisionSourceTests.swift")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def apply() -> None:
    source = APP.read_text(encoding="utf-8")
    old = '''        var redacted: [String: String] = [:]
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
'''
    new = '''        var redacted: [String: String] = [:]
        redacted.reserveCapacity(update.count)
        for (key, value) in update {
            var redactedKey = key.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )
            let redactedValue = value.replacingOccurrences(
                of: accountUID,
                with: "<redacted-account-uid>",
                options: [.caseInsensitive, .literal]
            )

            // Redacting identity-bearing key substrings can make two distinct source keys equal.
            // Preserve both opaque evidence fields instead of silently overwriting one.
            if redacted[redactedKey] != nil {
                var suffix = 2
                while redacted["\\(redactedKey)#\\(suffix)"] != nil {
                    suffix += 1
                }
                redactedKey = "\\(redactedKey)#\\(suffix)"
            }
            redacted[redactedKey] = redactedValue
        }
'''
    source = replace_once(source, old, new, "UID-redacted key collision preservation")
    APP.write_text(source, encoding="utf-8")

    TEST.write_text(r'''import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account-UID redacted key collision custody")
struct TuyaApplicationAccountUIDKeyCollisionSourceTests {
    @Test("UID redaction preserves distinct source fields that collapse to the same sanitized key")
    func redactedKeyCollisionsCannotEraseAcceptedEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let redactor = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(redactor.contains("var redactedKey = key.replacingOccurrences("))
        #expect(redactor.contains("let redactedValue = value.replacingOccurrences("))
        #expect(redactor.contains("if redacted[redactedKey] != nil"))
        #expect(redactor.contains("var suffix = 2"))
        #expect(redactor.contains("while redacted[\"\\(redactedKey)#\\(suffix)\"] != nil"))
        #expect(redactor.contains("redactedKey = \"\\(redactedKey)#\\(suffix)\""))
        #expect(redactor.contains("redacted[redactedKey] = redactedValue"))
    }

    @Test("trusted generation remains stamped after UID collision-safe redaction")
    func trustedGenerationStillOwnsReservedProvenance() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let redaction = try #require(receiver.range(of: "var eventDetails = redactedApplicationEventDetails(update)"))
        let generation = try #require(receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(redaction.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < log.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
''', encoding="utf-8")


def verify() -> None:
    source = APP.read_text(encoding="utf-8")
    required = [
        "var redactedKey = key.replacingOccurrences(",
        "let redactedValue = value.replacingOccurrences(",
        "if redacted[redactedKey] != nil",
        "var suffix = 2",
        'while redacted["\\(redactedKey)#\\(suffix)"] != nil',
        'redactedKey = "\\(redactedKey)#\\(suffix)"',
        "redacted[redactedKey] = redactedValue",
        'eventDetails["generation"] = String(token.diagnosticGeneration)',
    ]
    for token in required:
        if token not in source:
            raise SystemExit(f"missing expected collision-custody token: {token}")
    if not TEST.exists():
        raise SystemExit("missing focused UID key-collision regression")


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2 or sys.argv[1] not in {"apply", "verify"}:
        raise SystemExit("usage: materialize_capture_uid_redaction_collision.py apply|verify")
    apply() if sys.argv[1] == "apply" else verify()
