import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("account UID privacy is frozen before async chronology and same lease is rechecked before event custody")
    func acceptedEventFreezesAndRevalidatesExactLeasedAccountUID() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))

        let leaseCapture = try requiredOffset(containing: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters", in: receiver)
        let privacyFreeze = try requiredOffset(containing: "let eventDetailsAtAdmission = redactedApplicationEventDetails(", in: receiver)
        let packageAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let leaseRecheck = try requiredOffset(containing: "currentLeasedAccountUID == leasedAccountUID", in: receiver)
        let eventLog = try requiredOffset(containing: "log("tuya_application_update", eventDetails)", in: receiver)

        #expect(leaseCapture < privacyFreeze)
        #expect(privacyFreeze < packageAwait)
        #expect(packageAwait < leaseRecheck)
        #expect(leaseRecheck < eventLog)
        #expect(receiver.contains("currentConnectionToken == token"))
        #expect(receiver.contains("phase == .observing"))
        #expect(receiver.contains("accountIdentityLeaseIsAuthorized"))
        #expect(receiver.contains("application_event_authority_changed_before_custody"))
        #expect(!receiver.contains("var eventDetails = redactedApplicationEventDetails(update)"))
    }

    @Test("redaction helper cannot fall back to raw SDK content and preserves redacted-key collisions")
    func redactionHasNoRawFallbackAndPreservesKeyCount() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let helper = String(try section(
            in: receiver,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("leasedAccountUID: String"))
        #expect(helper.contains("key.replacingOccurrences("))
        #expect(helper.contains("value.replacingOccurrences("))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("options: [.caseInsensitive, .literal]"))
        #expect(helper.contains("update.sorted(by:"))
        #expect(helper.contains("while redacted[redactedKey] != nil"))
        #expect(helper.contains("collisionIndex += 1"))
        #expect(!helper.contains("return update"))
        #expect(!receiver.contains("log("tuya_application_update", update"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw Error.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            throw Error.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private enum Error: Swift.Error { case sectionMissing }
}
