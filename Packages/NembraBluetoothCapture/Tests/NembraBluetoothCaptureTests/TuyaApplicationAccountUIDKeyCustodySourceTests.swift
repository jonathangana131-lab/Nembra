import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID malformed-key custody")
struct TuyaApplicationAccountUIDKeyCustodySourceTests {
    @Test("exact verified account UID is scrubbed from keys and values before event custody")
    func accountUIDCannotSurviveKeyOrValueProjection() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source,
            from: "private static func redactVerifiedAccountUID(",
            to: "private func receivedApplicationUpdate("))
        let admission = String(try section(in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"))

        #expect(helper.contains("rawKey.replacingOccurrences("))
        #expect(helper.contains("rawValue.replacingOccurrences("))
        #expect(helper.components(separatedBy: "of: verifiedAccountUID").count - 1 == 2)
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("while redacted[admittedKey] != nil"))
        #expect(admission.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(admission.contains("let exportSafeUpdate = Self.redactVerifiedAccountUID("))
        #expect(admission.contains("exportSafeUpdate.merging(["))
        #expect(!admission.contains("update.merging(["))
        #expect(!admission.contains("OfficialTuyaFactory.currentAccountUID"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error { case sectionMissing }
}
