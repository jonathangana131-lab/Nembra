import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event admission custody")
struct TuyaApplicationEventCustodyAdmissionRaceSourceTests {
    @Test("leased account UID and lossless event details are snapshotted before the first suspension")
    func accountUIDCustodyIsAdmissionBound() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let lease = try #require(receiver.range(of: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters"))
        let custody = try #require(receiver.range(of: "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let account = try #require(receiver.range(of: "accountUID: leasedAccountUID"))
        let firstLedgerAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        #expect(lease.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < account.lowerBound)
        #expect(account.lowerBound < firstLedgerAwait.lowerBound)
    }

    @Test("post-suspension authority fence remains between ledger refresh and immutable event log")
    func authorityIsRevalidatedBeforeImmutableEventCustody() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let ledger = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        let refresh = try #require(receiver.range(of: "await refreshLedgerSnapshot()", range: ledger.upperBound..<receiver.endIndex))
        let tokenFence = try #require(receiver.range(of: "guard currentConnectionToken == token,", range: refresh.upperBound..<receiver.endIndex))
        let accountFence = try #require(receiver.range(of: "membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines) == leasedAccountUID", range: tokenFence.upperBound..<receiver.endIndex))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", custodySafeEventDetails)", range: accountFence.upperBound..<receiver.endIndex))

        #expect(ledger.lowerBound < refresh.lowerBound)
        #expect(refresh.lowerBound < tokenFence.lowerBound)
        #expect(tokenFence.lowerBound < accountFence.lowerBound)
        #expect(accountFence.lowerBound < log.lowerBound)
        #expect(receiver.contains("sdk_source_authority_changed_before_application_event_custody"))
    }

    @Test("trusted generation is frozen into package custody instead of overwriting opaque SDK evidence")
    func generationUsesNembraTokenAuthorityLosslessly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let generation = try #require(receiver.range(of: "trustedGeneration: String(token.diagnosticGeneration)", range: custody.upperBound..<receiver.endIndex))
        let ledger = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate", range: generation.upperBound..<receiver.endIndex))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", custodySafeEventDetails)", range: ledger.upperBound..<receiver.endIndex))
        #expect(custody.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < ledger.lowerBound)
        #expect(ledger.lowerBound < log.lowerBound)
        #expect(!receiver.contains("eventDetails[\"generation\"] ="))
        #expect(!receiver.contains("redactedApplicationEventDetails("))
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
