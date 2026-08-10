import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from keys and values")
    func acceptedApplicationEventScrubsExactAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start), let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
