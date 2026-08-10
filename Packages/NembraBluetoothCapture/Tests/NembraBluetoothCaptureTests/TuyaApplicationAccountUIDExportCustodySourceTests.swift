import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from untrusted keys and values")
    func acceptedEventScrubsExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
        #expect(!receiver.contains("return update"))
        #expect(receiver.contains("return nil"))
        #expect(receiver.contains("guard var eventDetails = redactedApplicationEventDetails(update) else"))
        #expect(receiver.contains("application_account_uid_custody_unavailable"))
        #expect(receiver.contains("while redacted[uniqueKey] != nil"))
        #expect(receiver.contains("collisionSuffix"))
        let custody = try #require(receiver.range(of: "guard var eventDetails = redactedApplicationEventDetails(update) else"))
        let ledger = try #require(receiver.range(of: "sessionLedger.recordApplicationUpdate"))
        #expect(custody.lowerBound < ledger.lowerBound)
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw Error.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum Error: Swift.Error { case sectionMissing }
}
