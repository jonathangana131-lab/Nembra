import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event custody across actor re-entry")
struct TuyaApplicationEventCustodyReentrancySourceTests {
    @Test("accepted event snapshots account UID before actor hop and revalidates authority before custody")
    func eventCustodyCannotUseRevokedMutableAccountState() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let snapshot = try requiredOffset(
            containing: "let admittedAccountUID = membershipAccountUID?.trimmingCharacters",
            in: receiver
        )
        let ledgerHop = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let refreshHop = try requiredOffset(
            containing: "await refreshLedgerSnapshot()",
            in: receiver
        )
        let postHopTokenGate = try requiredOffset(
            containing: "guard currentConnectionToken == token",
            in: receiver,
            after: refreshHop
        )
        let exactLeaseGate = try requiredOffset(
            containing: "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == admittedAccountUID",
            in: receiver,
            after: refreshHop
        )
        let redactionCall = try requiredOffset(
            containing: "accountUID: admittedAccountUID",
            in: receiver,
            after: refreshHop
        )
        let eventLog = try requiredOffset(
            containing: "log(\"tuya_application_update\"",
            in: receiver,
            after: refreshHop
        )

        #expect(snapshot < ledgerHop)
        #expect(ledgerHop < refreshHop)
        #expect(refreshHop < postHopTokenGate)
        #expect(postHopTokenGate < exactLeaseGate)
        #expect(exactLeaseGate < redactionCall)
        #expect(redactionCall < eventLog)
        #expect(receiver.contains("sdk_source_authority_changed_before_application_event_custody"))
    }

    @Test("UID redaction never falls back to raw update and preserves sanitized key collisions")
    func redactorFailsClosedAndPreservesEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("accountUID: String"))
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("let baseKey"))
        #expect(helper.contains("while redacted[admittedKey] != nil"))
        #expect(helper.contains("redacted[admittedKey]"))
        #expect(!helper.contains("return update"))
        #expect(!helper.contains("membershipAccountUID"))
    }

    private func requiredOffset(
        containing token: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> String.Index {
        let range = (lowerBound.map { $0..<source.endIndex } ?? source.startIndex..<source.endIndex)
        guard let found = source.range(of: token, range: range) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return found.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
