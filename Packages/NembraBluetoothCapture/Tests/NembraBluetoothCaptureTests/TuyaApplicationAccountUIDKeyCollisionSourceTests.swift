import Foundation
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
