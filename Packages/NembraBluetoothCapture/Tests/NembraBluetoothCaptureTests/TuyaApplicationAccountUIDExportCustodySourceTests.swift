import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from untrusted keys and values")
    func acceptedEventScrubsExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let scrub = try requiredOffset(containing: "let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: custodyAccountUID)", in: receiver)
        let ledgerAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        #expect(scrub < ledgerAwait)
        #expect(receiver.contains("guard let custodyAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("var eventDetails = custodySafeUpdate"))
        #expect(receiver.contains("for key in update.keys.sorted()"))
        #expect(receiver.contains("while redacted[outputKey] != nil"))
        #expect(receiver.contains("redacted[outputKey] = redactedValue"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("return update"))
        #expect(!receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw Error.sectionMissing }
        return range.lowerBound
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
