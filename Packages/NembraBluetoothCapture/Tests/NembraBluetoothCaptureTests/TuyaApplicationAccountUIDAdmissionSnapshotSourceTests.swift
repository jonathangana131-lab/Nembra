import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID admission snapshot")
struct TuyaApplicationAccountUIDAdmissionSnapshotSourceTests {
    @Test("leased account UID is snapshotted before the first actor suspension")
    func accountUIDCustodyPrecedesLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let custody = try requiredOffset(
            containing: "redactedApplicationEventDetails(update",
            in: receiver
        )
        let firstLedgerAwait = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let acceptedLog = try requiredOffset(
            containing: "log(\"tuya_application_update\", eventDetails)",
            in: receiver
        )

        #expect(custody < firstLedgerAwait)
        #expect(firstLedgerAwait < acceptedLog)
    }

    @Test("redactor consumes immutable admitted UID rather than mutable controller membership after suspension")
    func redactorIsBoundToAdmissionIdentity() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("accountUID:"))
        #expect(receiver.contains("redactedApplicationEventDetails(update"))

        let firstLedgerAwait = try requiredOffset(
            containing: "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        let tail = receiver[firstLedgerAwait...]
        #expect(!tail.contains("membershipAccountUID"))
        #expect(!tail.contains("redactedApplicationEventDetails(update"))
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
