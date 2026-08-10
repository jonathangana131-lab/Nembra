import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact admitted account UID from untrusted keys and values")
    func acceptedEventScrubsExactAdmittedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))

        #expect(receiver.contains("let admittedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("redactedApplicationEventDetails("))
        #expect(receiver.contains("accountUID: admittedAccountUID"))
        #expect(receiver.contains("let baseKey = redactedText(key)"))
        #expect(receiver.contains("redacted[admittedKey] = redactedText(value)"))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
        #expect(!receiver.contains("return update"))
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
