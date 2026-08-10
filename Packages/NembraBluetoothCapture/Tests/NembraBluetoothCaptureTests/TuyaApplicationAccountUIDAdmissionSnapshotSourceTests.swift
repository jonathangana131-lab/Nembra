import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID admission snapshot")
struct TuyaApplicationAccountUIDAdmissionSnapshotSourceTests {
    @Test("account UID is scrubbed from application evidence before the first actor suspension")
    func accountUIDScrubPrecedesLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let scrub = try requiredOffset(
            containing: "let exportSafeUpdate = redactedApplicationUpdateForEventCustody(update)",
            in: receiver
        )
        let firstLedgerAwait = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let acceptedLog = try requiredOffset(
            containing: "log(\"tuya_application_update\", exportSafeUpdate.merging([",
            in: receiver
        )

        #expect(scrub < firstLedgerAwait)
        #expect(firstLedgerAwait < acceptedLog)
    }

    @Test("accepted event custody never re-scrubs from mutable membership state after suspension")
    func acceptedLogUsesPreSuspensionSnapshot() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("let exportSafeUpdate = redactedApplicationUpdateForEventCustody(update)"))
        #expect(receiver.contains("log(\"tuya_application_update\", exportSafeUpdate.merging(["))

        let afterFirstAwait = receiver.range(of: "try await sessionLedger.recordApplicationUpdate")?.upperBound
        if let afterFirstAwait {
            let tail = receiver[afterFirstAwait...]
            #expect(!tail.contains("let exportSafeUpdate = redactedApplicationUpdateForEventCustody(update)"))
        } else {
            Issue.record("Expected application ledger await was missing")
        }
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
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
