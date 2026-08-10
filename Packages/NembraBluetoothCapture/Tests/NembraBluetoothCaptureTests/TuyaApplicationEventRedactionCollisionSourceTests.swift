import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya application event redaction collision custody")
struct TuyaApplicationEventRedactionCollisionSourceTests {
    @Test("account UID redaction cannot silently overwrite a distinct opaque application field")
    func redactedKeyCollisionMustPreserveBothFields() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let helper = String(try section(
            in: source,
            from: "private func redactedApplicationEventDetails(",
            to: "private func startWatchdog"
        ))

        // Exact current failure mode: two distinct input keys can become the same key after the
        // leased account UID is replaced, and a single dictionary subscript assignment silently
        // discards whichever opaque field was inserted first. Privacy redaction must not mutate
        // evidence cardinality without an explicit collision-preserving custody rule.
        #expect(!helper.contains("redacted[redactedKey] = value.replacingOccurrences("))

        // Keep the contract implementation-flexible while requiring an explicit deterministic
        // collision path. A repair may suffix/namespace colliding keys or delegate to a dedicated
        // custody helper, but it must not rely on Dictionary's last-write-wins behavior.
        #expect(
            helper.contains("collision")
                || helper.contains("unique")
                || helper.contains("occupied")
                || helper.contains("while redacted[")
                || helper.contains("TuyaApplicationEventCustody")
        )
        #expect(helper.contains("<redacted-account-uid>"))
        #expect(helper.contains("membershipAccountUID"))
    }

    @Test("trusted generation remains assigned after collision-safe application custody")
    func generationProvenanceRemainsNembraOwned() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let receiver = String(try section(
            in: source,
            from: "private func receivedApplicationUpdate(",
            to: "private func startWatchdog"
        ))

        let custody = try requiredOffset(containing: "redactedApplicationEventDetails(update)", in: receiver)
        let generation = try requiredOffset(
            containing: "eventDetails[\"generation\"] = String(token.diagnosticGeneration)",
            in: receiver
        )
        let log = try requiredOffset(containing: "log(\"tuya_application_update\", eventDetails)", in: receiver)

        #expect(custody < generation)
        #expect(generation < log)
    }

    private func requiredOffset(containing token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \(token)")
            throw ContractError.missing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let start = source.range(of: start),
              let end = source.range(of: end, range: start.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \(start) ... \(end)")
            throw ContractError.missing
        }
        return source[start.lowerBound..<end.lowerBound]
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

    private enum ContractError: Swift.Error { case missing }
}
