import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event scrubs the exact leased account UID from untrusted keys and values")
    func acceptedEventScrubsExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        #expect(receiver.contains("leasedAccountUID = membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("redactedApplicationEventDetails(update, accountUID: leasedAccountUID)"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(receiver.contains("while redacted[custodyKey] != nil"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("account identity and exact connection token are revalidated after ledger actor hops")
    func accountLeaseIsRecheckedBeforeImmutableEventCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func redactedApplicationEventDetails("))
        let snapshot = try requiredOffset("let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)", in: receiver)
        let ledger = try requiredOffset("try await sessionLedger.recordApplicationUpdate", in: receiver, after: snapshot)
        let refresh = try requiredOffset("await refreshLedgerSnapshot()", in: receiver, after: ledger)
        let postAwaitToken = try requiredOffset("guard currentConnectionToken == token,", in: receiver, after: refresh)
        let postAwaitUID = try requiredOffset("membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == leasedAccountUID", in: receiver, after: postAwaitToken)
        let custody = try requiredOffset("var eventDetails = custodySafeUpdate", in: receiver, after: postAwaitUID)
        let log = try requiredOffset("log(\"tuya_application_update\"", in: receiver, after: custody)

        #expect(snapshot < ledger)
        #expect(ledger < refresh)
        #expect(refresh < postAwaitToken)
        #expect(postAwaitToken < postAwaitUID)
        #expect(postAwaitUID < custody)
        #expect(custody < log)
        #expect(receiver.contains("sdk_source_authority_changed_before_application_event_custody"))
    }

    @Test("account UID custody is value-bound rather than a blanket generic uid-key rule")
    func accountUIDCustodyDoesNotEraseGenericDeviceUIDKeys() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    private func requiredOffset(
        _ token: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let searchRange = (lowerBound ?? source.startIndex)..<source.endIndex
        guard let range = source.range(of: token, range: searchRange) else {
            Issue.record("Expected source token missing: \(token)")
            throw Error.sectionMissing
        }
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
