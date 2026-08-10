import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application account UID export custody")
struct TuyaApplicationAccountUIDExportCustodySourceTests {
    @Test("accepted event binds UID scrubbing to the exact admitted account lease before suspension")
    func acceptedEventSnapshotsLeasedAccountUIDBeforeAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let uidSnapshot = try offset(
            "let verifiedAccountUID = membershipAccountUID?.trimmingCharacters(in: .whitespacesAndNewlines)",
            in: receiver
        )
        let custodyProjection = try offset(
            "let custodySafeUpdate = Self.redactedApplicationEventDetails(update, accountUID: verifiedAccountUID)",
            in: receiver
        )
        let firstLedgerAwait = try offset(
            "try await sessionLedger.recordApplicationUpdate",
            in: receiver
        )
        #expect(uidSnapshot < custodyProjection)
        #expect(custodyProjection < firstLedgerAwait)
        #expect(receiver.contains("!verifiedAccountUID.isEmpty"))
        #expect(receiver.contains("var eventDetails = custodySafeUpdate"))
        #expect(receiver.contains("eventDetails[\"generation\"] = String(token.diagnosticGeneration)"))
        #expect(!receiver.contains("log(\"tuya_application_update\", update"))
    }

    @Test("UID scrubber is lease-parameterized and preserves redacted-key collisions")
    func uidScrubberPreservesOpaqueApplicationEvidence() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        #expect(receiver.contains("private static func redactedApplicationEventDetails("))
        #expect(receiver.contains("accountUID: String"))
        #expect(!receiver.contains("membershipAccountUID?.trimmingCharacters"))
        #expect(receiver.contains("update.sorted(by: { $0.key < $1.key })"))
        #expect(receiver.contains("let redactedKey = key.replacingOccurrences("))
        #expect(receiver.contains("value.replacingOccurrences("))
        #expect(receiver.contains("<redacted-account-uid>"))
        #expect(receiver.contains("options: [.caseInsensitive, .literal]"))
        #expect(receiver.contains("while redacted[custodyKey] != nil"))
        #expect(receiver.contains("custodyKey = \"\\(redactedKey)#\\(collisionIndex)\""))
        #expect(receiver.contains("collisionIndex += 1"))
    }

    private func offset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else { throw Error.sectionMissing }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
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

    private enum Error: Swift.Error { case sectionMissing }
}
