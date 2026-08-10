import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-event authority custody")
struct TuyaApplicationEventAuthorityCustodySourceTests {
    @Test("verified account UID is snapshotted before actor hops and redacted from accepted event details")
    func verifiedAccountUIDCannotLeakThroughApplicationEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        guard let uidSnapshot = receiver.range(of: "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)"),
              let firstLedgerAwait = receiver.range(of: "try await sessionLedger.recordApplicationUpdate"),
              let eventLog = receiver.range(of: "log(\"tuya_application_update\"") else {
            Issue.record("Could not isolate UID snapshot, ledger admission, and event custody ordering.")
            throw SourceContractError.sectionMissing
        }

        #expect(uidSnapshot.lowerBound < firstLedgerAwait.lowerBound)
        #expect(firstLedgerAwait.lowerBound < eventLog.lowerBound)
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("replacingOccurrences(of: verifiedAccountUID"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update.merging(["))
    }

    @Test("Nembra generation metadata wins every SDK key collision")
    func trustedGenerationWinsReservedMetadataCollision() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        guard let details = receiver.range(of: "var eventDetails"),
              let trustedGeneration = receiver.range(of: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)"),
              let eventLog = receiver.range(of: "log(\"tuya_application_update\", eventDetails)") else {
            Issue.record("Could not isolate trusted application-event metadata construction.")
            throw SourceContractError.sectionMissing
        }

        #expect(details.lowerBound < trustedGeneration.lowerBound)
        #expect(trustedGeneration.lowerBound < eventLog.lowerBound)
        #expect(!receiver.contains(") { current, _ in current })"))
    }

    @Test("account UID custody is value-bound rather than a blanket generic uid-key rule")
    func custodyDoesNotEraseAllGenericUIDEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let driver = String(try section(
            in: source,
            from: "@MainActor\nprivate final class SmartLifeDriver",
            to: "#endif\n\nprivate enum AppleAccountAuthorizationError"
        ))

        #expect(!driver.contains("\"uid\","))
        #expect(!driver.contains("\"uid\"\n"))
    }

    @Test("event custody cannot grow physical or command authority")
    func custodyRemainsPresentationAndExportOnly() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        for forbidden in ["disconnectBLE", "publishDps", "queryDps", "writeValue"] {
            #expect(!receiver.contains(forbidden))
        }
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

    private enum SourceContractError: Error { case sectionMissing }
}
