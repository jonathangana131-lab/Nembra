import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya account UID redaction collision custody")
struct TuyaApplicationAccountUIDRedactionCollisionSourceTests {
    @Test("UID key redaction cannot silently overwrite a second accepted application field")
    func redactedKeyCollisionsPreserveBothOpaqueFields() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("update.sorted(by: { $0.key < $1.key })"))
        #expect(helper.contains("var uniqueKey = redactedKey"))
        #expect(helper.contains("while redacted[uniqueKey] != nil"))
        #expect(helper.contains("uniqueKey = \"\\(redactedKey)#\\(collisionSuffix)\""))
        #expect(helper.contains("redacted[uniqueKey] = redactedValue"))
        #expect(!helper.contains("redacted[redactedKey] = value.replacingOccurrences("))
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
