import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture failed stage-rail accessibility truth")
struct CaptureFailedStageRailAccessibilitySourceTests {
    @Test("failed Capture uses an explicit stopped rail before normal procedure stages")
    func failedRailDoesNotPresentTargetAsCurrent() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let stageRail = String(try section(
            in: source,
            from: "private var stageRail: some View",
            to: "private var primarySurface: some View"
        ))

        let failedMarker = try #require(stageRail.range(of: "if test.phase == .failed"))
        let normalRailMarker = try #require(stageRail.range(of: "else if dynamicTypeSize.isAccessibilitySize"))
        #expect(failedMarker.lowerBound < normalRailMarker.lowerBound)

        let failedPrefix = String(stageRail[..<normalRailMarker.lowerBound])
        #expect(failedPrefix.contains("Attempt stopped"))
        #expect(failedPrefix.contains("Capture attempt stopped"))
        #expect(failedPrefix.contains("accessibilityLabel"))
        #expect(failedPrefix.contains("accessibilityValue"))
        #expect(failedPrefix.contains("Begin again from scooter OFF"))
        #expect(failedPrefix.contains("Relaunch before another attempt"))
    }

    @Test("failed product copy is terminal rather than resumable")
    func failedHeroAndPanelsUseStoppedLanguage() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let phaseTitle = String(try section(
            in: source,
            from: "private var phaseTitle: String",
            to: "private var phaseSubtitle: String"
        ))
        let failedPanels = String(try section(
            in: source,
            from: "private var failureRecoveryContextPanel: some View",
            to: "private var failureDiagnosticsControls: some View"
        ))

        #expect(phaseTitle.contains("case .failed: return \"Capture stopped\""))
        #expect(!phaseTitle.contains("case .failed: return \"Capture paused\""))
        #expect(!failedPanels.contains("Capture paused"))
        #expect(failedPanels.components(separatedBy: "Capture stopped").count - 1 == 2)
        #expect(failedPanels.contains("This stopped attempt will not be reused."))
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
