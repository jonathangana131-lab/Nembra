import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event delegates exact leased account UID custody before logging")
    func acceptedEventDelegatesExactLeasedAccountUIDCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let accountUID = try #require(receiver.range(of: "accountUID: membershipAccountUID"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(custody.lowerBound < accountUID.lowerBound)
        #expect(accountUID.lowerBound < log.lowerBound)
        #expect(!receiver.contains("redactedApplicationEventDetails(update)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
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
