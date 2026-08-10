import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted stage-rail accessibility")
struct CaptureAcceptedStageRailAccessibilitySourceTests {
    @Test("accepted Seal state announces the final step complete, matching its checkmark")
    func acceptedSealStepDoesNotRemainCurrentToVoiceOver() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let stageRail = String(try section(
            in: source,
            from: "private var stageRail: some View",
            to: "private var primarySurface: some View"
        ))

        // The accepted UI already renders every stage as a completed checkmark.
        #expect(stageRail.contains("index < currentStageIndex || test.phase == .accepted"))

        // VoiceOver must consume that same accepted-state truth. Otherwise Seal is
        // visually complete while assistive technology still announces it as current.
        guard let accessibilityLine = stageRail
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.contains(".accessibilityLabel(\"Step") }) else {
            Issue.record("Stage rail accessibility label is missing")
            throw SourceContractError.sectionMissing
        }
        #expect(accessibilityLine.contains("test.phase == .accepted"))
        #expect(accessibilityLine.contains("complete"))
    }

    @Test("stage rail keeps explicit current complete and upcoming semantics")
    func stageRailKeepsThreeSemanticStates() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let stageRail = String(try section(
            in: source,
            from: "private var stageRail: some View",
            to: "private var primarySurface: some View"
        ))

        #expect(stageRail.contains("current"))
        #expect(stageRail.contains("complete"))
        #expect(stageRail.contains("upcoming"))
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
