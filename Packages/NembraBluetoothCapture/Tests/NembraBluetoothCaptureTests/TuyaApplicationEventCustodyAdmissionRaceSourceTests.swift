import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event admission custody")
struct TuyaApplicationEventCustodyAdmissionRaceSourceTests {
    @Test("leased account UID is snapshotted before the first suspension")
    func accountUIDCustodyIsAdmissionBound() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let lease = try #require(receiver.range(of: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters"))
        let custody = try #require(receiver.range(of: "let custodySafeUpdate = redactedApplicationEventDetails(update, accountUID: leasedAccountUID)"))
        let firstLedgerAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        #expect(lease.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < firstLedgerAwait.lowerBound)
    }

    @Test("redactor cannot fail open by rereading mutable membership state")
    func redactorUsesOnlyAdmissionSnapshot() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("accountUID: String"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(!helper.contains("return update"))
    }

    @Test("redaction-key collisions retain every admitted opaque entry")
    func redactionCollisionDoesNotDropEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        #expect(helper.contains("update.sorted"))
        #expect(helper.contains("collisionOrdinal"))
        #expect(helper.contains("while redacted[custodyKey] != nil"))
        #expect(helper.contains("redacted[custodyKey] = redactedValue"))
        #expect(!helper.contains("redacted[redactedKey] = value.replacingOccurrences"))
    }

    @Test("trusted generation stamp remains after sanitized custody creation")
    func generationStillUsesNembraTokenAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))

        let details = try #require(receiver.range(of: "var eventDetails = custodySafeUpdate"))
        let stamp = try #require(receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", eventDetails)"))
        #expect(details.lowerBound < stamp.lowerBound)
        #expect(stamp.lowerBound < log.lowerBound)
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
