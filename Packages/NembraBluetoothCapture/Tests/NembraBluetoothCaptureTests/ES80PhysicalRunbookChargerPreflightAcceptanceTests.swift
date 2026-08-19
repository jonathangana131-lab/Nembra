import Foundation
import Testing

@Suite("ES80 physical runbook charger preflight")
struct ES80PhysicalRunbookChargerPreflightAcceptanceTests {
    @Test("current secure-link procedure requires fresh operator safety declarations without claiming charger measurement")
    func secureLinkRequiresCurrentAttemptSafetyDeclarationsWithoutClaimingChargerTelemetry() throws {
        let secureLinkRunbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")
        let secureLinkRunbookLower = secureLinkRunbook.lowercased()

        #expect(secureLinkRunbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(secureLinkRunbook.contains("repository explicitly records `GO`"))
        #expect(secureLinkRunbook.contains("physical secure-link experiment is **NO-GO**"))

        let preflight = try section(
            in: secureLinkRunbook,
            from: "### Preflight",
            to: "### Fresh four-window target correlation"
        ).lowercased()
        #expect(preflight.contains("for this current attempt"))
        #expect(preflight.contains("require the operator to freshly declare in capture"))
        #expect(preflight.contains("powered **off**, stationary"))
        #expect(preflight.contains("its charger is physically disconnected"))
        #expect(preflight.contains("no riding will occur"))
        #expect(preflight.contains("a declaration from an earlier attempt is stale"))
        #expect(preflight.contains("not charger sensing, charger telemetry"))

        let supportedSession = try section(
            in: secureLinkRunbook,
            from: "### Supported read-only Tuya session",
            to: "### Stop conditions"
        )
        let supportedSessionLower = supportedSession.lowercased()

        // Charger truth is an explicit current-attempt operator declaration, not telemetry.
        // The supported session must retain that physical state and the sole-owner/no-command
        // boundary throughout the canonical 45-second observation.
        #expect(supportedSessionLower.contains("current-attempt operator declarations remain true"))
        #expect(supportedSessionLower.contains("keep its charger physically disconnected"))
        #expect(supportedSessionLower.contains("do not ride"))
        #expect(supportedSessionLower.contains("at least 45 seconds of canonical authenticated observation"))
        #expect(supportedSessionLower.contains("nembra sends no scooter dp query/control command"))
        #expect(supportedSessionLower.contains("opens no second corebluetooth connection"))

        let safetyBoundary = try section(
            in: secureLinkRunbook,
            from: "## Safety boundary",
            to: "After PASS"
        ).lowercased()
        #expect(safetyBoundary.contains("freshly declared by the operator for each attempt"))
        #expect(safetyBoundary.contains("nembra does not measure charger state"))
        #expect(safetyBoundary.contains("sense the charger"))
        #expect(safetyBoundary.contains("infer these physical preconditions from ble/sdk telemetry"))

        // Reject positive charger-sensing or telemetry-authority claims anywhere in the canonical
        // procedure while allowing the explicit negative safety boundary above.
        #expect(!secureLinkRunbookLower.contains("charger state is measured"))
        #expect(!secureLinkRunbookLower.contains("nembra senses the charger"))
        #expect(!secureLinkRunbookLower.contains("charger telemetry confirms"))
    }

    private func section(in text: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(text.range(of: startMarker)?.lowerBound)
        let end = try #require(text.range(of: endMarker, range: start..<text.endIndex)?.lowerBound)
        return String(text[start..<end])
    }

    private func repositoryFile(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
