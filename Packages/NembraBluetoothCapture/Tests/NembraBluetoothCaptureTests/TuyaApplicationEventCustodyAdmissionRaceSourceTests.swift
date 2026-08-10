import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event admission custody")
struct TuyaApplicationEventCustodyAdmissionRaceSourceTests {
    @Test("leased account UID is snapshotted and custody is built before the first suspension")
    func accountUIDCustodyIsAdmissionBound() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let lease = try #require(receiver.range(of: "let leasedAccountUID = membershipAccountUID?.trimmingCharacters"))
        let custody = try #require(receiver.range(of: "let custodySafeEventDetails = TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let accountSnapshot = try #require(receiver.range(of: "accountUID: leasedAccountUID"))
        let firstLedgerAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        #expect(lease.lowerBound < custody.lowerBound)
        #expect(custody.lowerBound < accountSnapshot.lowerBound)
        #expect(accountSnapshot.lowerBound < firstLedgerAwait.lowerBound)
    }

    @Test("post-suspension event path cannot reread mutable membership identity")
    func eventCustodyUsesOnlyAdmissionSnapshot() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let firstLedgerAwait = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))
        let postSuspension = receiver[firstLedgerAwait.lowerBound...]
        #expect(!postSuspension.contains("membershipAccountUID"))
        #expect(postSuspension.contains("log(\"tuya_application_update\", custodySafeEventDetails)"))
    }

    @Test("trusted generation enters custody before application data becomes immutable event evidence")
    func generationUsesConnectionTokenAuthority() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let custody = try #require(receiver.range(of: "TuyaAuthenticatedApplicationEventCustody.eventDetails("))
        let generation = try #require(receiver.range(of: "trustedGeneration: String(token.diagnosticGeneration)"))
        let log = try #require(receiver.range(of: "log(\"tuya_application_update\", custodySafeEventDetails)"))
        #expect(custody.lowerBound < generation.lowerBound)
        #expect(generation.lowerBound < log.lowerBound)
        #expect(!receiver.contains("eventDetails[\"generation\"] ="))
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
