import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application-event privacy across async custody")
struct TuyaApplicationEventPrivacyReentrancySourceTests {
    @Test("leased account UID is removed before the first suspension in event admission")
    func privacyMaterializationPrecedesFirstAwait() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func redactedApplicationEventDetails("
        ))

        let privacyMaterialization = try #require(receiver.range(of: "redactedApplicationEventDetails(update)"))
        let firstSuspension = try #require(receiver.range(of: "try await sessionLedger.recordApplicationUpdate"))

        // The lease is valid at the synchronous admission guard. Materialize the privacy-safe
        // SDK detail copy before yielding MainActor so a concurrent foreground/account revocation
        // cannot clear membershipAccountUID and make the redactor fall back to raw event details.
        #expect(privacyMaterialization.lowerBound < firstSuspension.lowerBound)
        #expect(receiver.contains("accountIdentityLeaseIsAuthorized"))
    }

    @Test("account-UID key redaction cannot silently overwrite a colliding evidence field")
    func redactionCreatedKeyCollisionsArePreservedDeterministically() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        // Two distinct untrusted keys can collapse to the same sanitized key when one contains
        // the exact leased account UID. Preserve both opaque evidence values instead of allowing
        // dictionary assignment to discard whichever value happens to be visited first.
        #expect(helper.contains("update.keys.sorted()"))
        #expect(helper.contains("while redacted[redactedKey] != nil") || helper.contains("while redacted[admittedKey] != nil"))
        #expect(helper.contains("collision"))
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let a = source.range(of: start),
              let b = source.range(of: end, range: a.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw SourceContractError.sectionMissing
        }
        return source[a.lowerBound..<b.lowerBound]
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
