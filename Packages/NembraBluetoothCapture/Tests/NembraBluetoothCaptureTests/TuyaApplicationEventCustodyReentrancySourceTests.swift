import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event custody reentrancy")
struct TuyaApplicationEventCustodyReentrancySourceTests {
    @Test("account UID custody is frozen before accepted ledger suspension")
    func custodyPrecedesAcceptedLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))

        let custody = try requiredRange(
            containing: "guard let custodySafeUpdate = redactedApplicationEventDetails(update)",
            in: receiver
        )
        let ledgerMutation = try requiredRange(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let refresh = try requiredRange(containing: "await refreshLedgerSnapshot()", in: receiver)
        let eventLog = try requiredRange(
            containing: "log(\"tuya_application_update\", eventDetails)",
            in: receiver
        )

        #expect(custody.lowerBound < ledgerMutation.lowerBound)
        #expect(custody.lowerBound < refresh.lowerBound)
        #expect(ledgerMutation.lowerBound < eventLog.lowerBound)
        #expect(receiver.contains("var eventDetails = custodySafeUpdate"))
        #expect(!receiver.contains("var eventDetails = redactedApplicationEventDetails(update)"))
    }

    @Test("missing lease identity fails closed and redaction cannot erase colliding evidence")
    func redactorIsFailClosedAndCollisionPreserving() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("-> [String: String]?"))
        #expect(helper.contains("!accountUID.isEmpty else { return nil }"))
        #expect(!helper.contains("return update"))
        #expect(helper.contains("for key in update.keys.sorted()"))
        #expect(helper.contains("while redacted[uniqueKey] != nil"))
        #expect(helper.contains("uniqueKey = \"\\(redactedKey)#\\(collisionSuffix)\""))
        #expect(helper.contains("<redacted-account-uid>"))
    }

    private func requiredRange(containing token: String, in source: String) throws -> Range<String.Index> {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range
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
