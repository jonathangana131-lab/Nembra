import Foundation
import Testing

@Suite("ES80 physical runbook charger preflight")
struct ES80PhysicalRunbookChargerPreflightAcceptanceTests {
    @Test("current secure-link procedure freezes charger state without claiming charger measurement")
    func secureLinkPinsStationaryChargerStateWithoutRevivingRetiredAuthority() throws {
        let retiredRunbook = try repositoryFile("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")
        let secureLinkRunbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        // The former passive runbook is intentionally retained only as a NO-GO tombstone.
        // Current field authority belongs to the authenticated stationary secure-link procedure.
        #expect(retiredRunbook.contains("Status: **RETIRED / NON-AUTHORITATIVE / PHYSICAL NO-GO.**"))
        #expect(retiredRunbook.contains("`docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md`"))
        #expect(retiredRunbook.contains("`ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(!retiredRunbook.contains("## Intended preflight once GO is authorized"))

        #expect(secureLinkRunbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(secureLinkRunbook.contains("repository explicitly records `GO`"))
        #expect(secureLinkRunbook.contains("physical secure-link experiment is **NO-GO**"))

        let supportedSession = try section(
            in: secureLinkRunbook,
            from: "### Supported read-only Tuya session",
            to: "### Stop conditions"
        )
        let supportedSessionLower = supportedSession.lowercased()

        // Charger truth is operational here, not telemetry: the operator must keep the physical
        // state unchanged during this stationary read-only preflight. Nembra must not invent a
        // charger sensor/declaration gate or weaken the sole-owner/no-command boundary.
        #expect(supportedSessionLower.contains("do not change mode/light/brake/throttle/charger state during this preflight"))
        #expect(supportedSessionLower.contains("nembra sends no scooter dp query/control command"))
        #expect(supportedSessionLower.contains("opens no second corebluetooth connection"))
        #expect(!supportedSessionLower.contains("charger state is measured"))
        #expect(!supportedSessionLower.contains("nembra senses the charger"))
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
