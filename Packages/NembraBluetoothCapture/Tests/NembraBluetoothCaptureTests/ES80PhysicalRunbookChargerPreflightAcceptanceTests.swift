import Foundation
import Testing

@Suite("ES80 authenticated stationary charger-state preflight")
struct ES80PhysicalRunbookChargerPreflightAcceptanceTests {
    @Test("current secure-link procedure freezes charger state without inventing charger sensing")
    func currentProcedureKeepsChargerStateStationary() throws {
        let runbook = try repositoryFile("docs/CAPTURE_P0_SECURE_LINK_NEXT_TEST.md")

        #expect(runbook.contains("PROCEDURE_ID: `ES80-AUTHENTICATED-STATIONARY-v1`"))
        #expect(runbook.contains("This test is indoors and stationary."))
        #expect(
            runbook.contains(
                "do not change mode/light/brake/throttle/charger state during this preflight."
            )
        )
        #expect(
            runbook.contains(
                "Nembra sends no scooter DP query/control command and opens no second CoreBluetooth connection."
            )
        )
        #expect(runbook.contains("Until all applicable software/private-device prerequisites are true and the repository explicitly records `GO`, the physical secure-link experiment is **NO-GO**."))

        // The current procedure preserves charger state as an operator/environment condition. It
        // does not claim that Nembra has measured, inferred, or confirmed a physical charger state.
        let lower = runbook.lowercased()
        #expect(!lower.contains("nembra measured the charger"))
        #expect(!lower.contains("nembra sensed the charger"))
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
