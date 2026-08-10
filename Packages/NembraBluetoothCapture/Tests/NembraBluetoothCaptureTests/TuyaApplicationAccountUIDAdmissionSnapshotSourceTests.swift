import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account-UID admission snapshot")
struct TuyaApplicationAccountUIDAdmissionSnapshotSourceTests {
    @Test("leased account UID and export-safe details are frozen before actor suspension")
    func accountUIDCustodyPrecedesLedgerAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(in: source, from: "private func receivedApplicationUpdate(", to: "private func startWatchdog"))
        let snapshot = try requiredOffset(containing: "let admittedAccountUID = membershipAccountUID?", in: receiver)
        let custody = try requiredOffset(containing: "redactedApplicationEventDetails(update, accountUID: admittedAccountUID)", in: receiver)
        let generation = try requiredOffset(containing: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)", in: receiver)
        let firstAwait = try requiredOffset(containing: "try await sessionLedger.recordApplicationUpdate", in: receiver)
        let log = try requiredOffset(containing: "log(\"tuya_application_update\", eventDetails)", in: receiver)
        #expect(snapshot < custody)
        #expect(custody < generation)
        #expect(generation < firstAwait)
        #expect(firstAwait < log)
        let tail = receiver[firstAwait...]
        #expect(!tail.contains("membershipAccountUID"))
        #expect(!tail.contains("redactedApplicationEventDetails(update"))
    }

    @Test("redactor consumes explicit admitted UID and fails closed for an empty identity")
    func redactorDoesNotReachBackIntoMembershipState() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(in: source, from: "private func redactedApplicationEventDetails(", to: "private func startWatchdog"))
        #expect(helper.contains("accountUID rawAccountUID: String"))
        #expect(!helper.contains("membershipAccountUID"))
        #expect(helper.contains("guard !accountUID.isEmpty else { return [:] }"))
        #expect(helper.contains("while redacted[\"\\(redactedKey)#\\(suffix)\"] != nil"))
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw SourceContractError.sectionMissing }
        return range.lowerBound
    }
    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start), let b = source.range(of: end, range: a.upperBound..<source.endIndex) else { throw SourceContractError.sectionMissing }
        return source[a.lowerBound..<b.lowerBound]
    }
    private func readRepositoryFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
    private enum SourceContractError: Error { case sectionMissing }
}
