import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event redaction collisions")
struct TuyaApplicationEventRedactionCollisionSourceTests {
    @Test("account UID redaction cannot silently overwrite a distinct application field")
    func redactionPreservesCollidingFields() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        // Two malformed SDK keys can become identical after the verified account UID is replaced.
        // Event custody must retain both values under safe deterministic keys instead of letting
        // Dictionary subscript assignment erase whichever field happened to be admitted first.
        #expect(helper.contains("for key in update.keys.sorted()"))
        #expect(helper.contains("var admittedKey = redactedKey"))
        #expect(helper.contains("while redacted[admittedKey] != nil"))
        #expect(helper.contains("collisionIndex"))
        #expect(helper.contains("redacted[admittedKey] = redactedValue"))
        #expect(!helper.contains("redacted[redactedKey] = value.replacingOccurrences"))

        // Collision disambiguation must not reinsert the sensitive UID.
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(!helper.contains("admittedKey = \"\\(redactedKey)#\\(accountUID)\""))
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
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
