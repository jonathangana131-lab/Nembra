import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from untrusted keys and values")
    func acceptedEventScrubsExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("redactedApplicationEventDetails(update, accountUID: membershipAccountUID)"))
        #expect(receiver.contains("let membershipAccountUID,"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("verified account UID is snapshotted and application content is scrubbed before the first actor yield")
    func accountUIDCannotBeRevokedBetweenAdmissionAndScrubbing() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))

        let snapshot = try requiredOffset(containing: "let membershipAccountUID,", in: receiver)
        let scrub = try requiredOffset(containing: "let exportSafeUpdate = redactedApplicationEventDetails(update, accountUID: membershipAccountUID)", in: receiver)
        let firstAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let log = try requiredOffset(containing: "log(\"tuya_application_update\", eventDetails)", in: receiver)

        #expect(snapshot < scrub)
        #expect(scrub < firstAwait)
        #expect(firstAwait < log)

        let helper = String(try section(
            in: receiver,
            from: "private static func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))
        #expect(helper.contains("accountUID: String"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(!helper.contains("return update"))
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
