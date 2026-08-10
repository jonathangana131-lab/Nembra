import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event snapshots and scrubs the leased account UID before ledger suspension")
    func acceptedEventScrubsExactLeasedAccountUIDBeforeLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let admission = try requiredOffset(
            containing: "applicationUpdateAdmissionsInFlight += 1",
            in: receiver
        )
        let uidSnapshot = try requiredOffset(
            containing: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters",
            in: receiver
        )
        let scrub = try requiredOffset(
            containing: "let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)",
            in: receiver
        )
        let ledgerAwait = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let safeEvent = try requiredOffset(
            containing: "var eventDetails = custodySafeUpdate",
            in: receiver
        )
        let trustedGeneration = try requiredOffset(
            containing: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)",
            in: receiver
        )
        let acceptedLog = try requiredOffset(
            containing: "log(\"tuya_application_update\", eventDetails)",
            in: receiver
        )

        #expect(admission < uidSnapshot)
        #expect(uidSnapshot < scrub)
        #expect(scrub < ledgerAwait)
        #expect(ledgerAwait < safeEvent)
        #expect(safeEvent < trustedGeneration)
        #expect(trustedGeneration < acceptedLog)
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("account UID scrubber is bound to the admission-time snapshot and never falls back to raw update")
    func scrubberCannotRereadMutableMembershipStateOrReturnRawUpdate() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))
        let helper = String(try section(
            in: receiver,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("accountUID: String"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(!helper.contains("return update"))
        #expect(helper.contains("let redactedKey = key.replacingOccurrences("))
        #expect(helper.contains("let redactedValue = value.replacingOccurrences("))
        #expect(helper.contains("of: accountUID"))
        #expect(helper.contains("with: \"<redacted-account-uid>\""))
        #expect(helper.contains("options: [.caseInsensitive, .literal]"))
        #expect(helper.contains("while redacted[custodyKey] != nil"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw Error.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
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

    private enum Error: Swift.Error {
        case sectionMissing
    }
}
