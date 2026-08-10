import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed stage-rail accessibility truth")
struct CaptureFailedStageRailAccessibilitySourceTests {
    @Test("failed Capture intercepts the normal procedure rail with terminal semantics")
    func failedRailDoesNotPresentAnyProcedureStepAsCurrent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let rail = String(try section(
            in: source,
            from: "private var stageRail: some View",
            to: "private var primarySurface: some View"
        ))

        let failed = try #require(rail.range(of: "if test.phase == .failed"))
        let normal = try #require(rail.range(of: "else if dynamicTypeSize.isAccessibilitySize"))
        #expect(failed.lowerBound < normal.lowerBound)

        let terminal = String(rail[..<normal.lowerBound])
        #expect(terminal.contains("CAPTURE STOPPED"))
        #expect(terminal.contains("No Capture step is current"))
        #expect(terminal.contains("Clear the blocker, then begin again from scooter OFF."))
        #expect(terminal.contains("Relaunch Capture before another attempt."))
        #expect(terminal.contains("accessibilityLabel"))
        #expect(terminal.contains("accessibilityValue"))
        #expect(!terminal.contains("Step 1"))
        #expect(!terminal.contains("Target, current"))
    }

    @Test("all visible failed-state titles use terminal stopped language")
    func failedHeroAndPanelsCannotImplyResumability() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let phaseTitle = String(try section(
            in: source,
            from: "private var phaseTitle: String",
            to: "private var phaseSubtitle: String"
        ))
        let panels = String(try section(
            in: source,
            from: "private var failureRecoveryContextPanel: some View",
            to: "private var failureDiagnosticsControls: some View"
        ))

        #expect(phaseTitle.contains("case .failed: return \"Capture stopped\""))
        #expect(!phaseTitle.contains("Capture paused"))
        #expect(!panels.contains("Capture paused"))
        #expect(panels.components(separatedBy: "Capture stopped").count - 1 == 2)
        #expect(panels.contains("This stopped attempt will not be reused."))
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
