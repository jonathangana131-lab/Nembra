import Foundation
import Testing

@Suite("ES80 physical runbook charger preflight")
struct ES80PhysicalRunbookChargerPreflightAcceptanceTests {
    @Test("field runbook mirrors the app's per-run disconnected-charger declaration")
    func runbookPinsChargerDeclarationWithoutPromotingItToMeasuredTruth() throws {
        let app = try repositoryFile("NembraApp/App/NembraApp.swift")
        let runbook = try repositoryFile("docs/ES80_PHYSICAL_CAPTURE_RUNBOOK.md")

        // The real product already makes this a fresh-run operator declaration: connected is
        // explicitly blocked, disconnected is required for the whole capture, and the UI states
        // that Nembra cannot sense the charger directly. The field procedure must not be weaker.
        #expect(app.contains("Keep charger unplugged for the whole capture"))
        #expect(app.contains("Unplug charger to continue"))
        #expect(app.contains("Nembra cannot sense the charger directly"))
        #expect(app.contains("selectedChargerState = nil"))

        let preflight = try section(
            in: runbook,
            from: "## Intended preflight once GO is authorized",
            to: "## Experiment One — target correlation and passive fingerprint"
        )
        let stopConditions = try section(
            in: runbook,
            from: "## Stop / failure conditions once GO exists",
            to: "## Current physical conclusion"
        )

        let preflightLower = preflight.lowercased()
        #expect(preflightLower.contains("charger"))
        #expect(preflightLower.contains("disconnected"))
        #expect(preflightLower.contains("declar"))
        #expect(preflightLower.contains("not") && (preflightLower.contains("measured") || preflightLower.contains("sense")))

        // Because the app tells the rider to keep the charger disconnected for the whole capture,
        // the eventual GO procedure must say what to do if that declared setup stops being true.
        let stopLower = stopConditions.lowercased()
        #expect(stopLower.contains("charger"))
        #expect(stopLower.contains("stop") || stopLower.contains("restart"))
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
