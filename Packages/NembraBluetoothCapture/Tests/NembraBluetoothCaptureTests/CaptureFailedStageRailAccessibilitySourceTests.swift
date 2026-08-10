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

        let failedMarker = try requiredOffset("if test.phase == .failed", in: stageRail)
        let normalRailMarker = try requiredOffset("dynamicTypeSize.isAccessibilitySize", in: stageRail)
        #expect(failedMarker < normalRailMarker)

        let failedPrefix = String(stageRail[failedMarker..<normalRailMarker])
        #expect(failedPrefix.contains("Attempt stopped"))
        #expect(failedPrefix.contains("No Capture step is current"))
        #expect(failedPrefix.contains("accessibilityLabel"))
        #expect(failedPrefix.contains("Capture stopped. No Capture step is current."))
        #expect(!failedPrefix.contains("stageLabels[currentStageIndex]"))
        #expect(!failedPrefix.contains("Step \\(currentStageIndex + 1)"))
    }

    @Test("failed phase copy cannot imply that the stopped attempt is resumable")
    func failedHeroUsesTerminalLanguage() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        let phaseTitle = String(try section(
            in: source,
            from: "private var phaseTitle: String",
            to: "private var phaseSubtitle: String"
        ))

        #expect(!phaseTitle.contains("case .failed: return \"Capture paused\""))
        #expect(phaseTitle.contains("case .failed: return \"Capture stopped\""))
    }

    @Test("failed panels use the same terminal language as the hero")
    func failurePanelsDoNotSayPaused() throws {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        #expect(!source.contains("Label(\"Capture paused\", systemImage: \"exclamationmark.circle\")"))
        #expect(source.components(separatedBy: "Label(\"Capture stopped\", systemImage: \"exclamationmark.circle\")").count - 1 == 2)
    }

    private func requiredOffset(_ token: String, in source: String) throws -> String.Index {
        guard let range = source.range(of: token) else {
            Issue.record("Expected source token missing: \\(token)")
            throw SourceContractError.sectionMissing
        }
        return range.lowerBound
    }

    private func section(in source: String, from start: String, to end: String) throws -> Substring {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            Issue.record("Expected source section missing: \\(start) ... \\(end)")
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
