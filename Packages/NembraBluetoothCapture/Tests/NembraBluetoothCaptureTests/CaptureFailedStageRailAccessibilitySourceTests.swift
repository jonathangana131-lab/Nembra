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

        guard let failedMarker = stageRail.range(of: "test.phase == .failed"),
              let normalRailMarker = stageRail.range(of: "dynamicTypeSize.isAccessibilitySize") else {
            Issue.record("Failed Capture must have explicit stage-rail semantics before the normal stage rail")
            throw SourceContractError.sectionMissing
        }

        #expect(failedMarker.lowerBound < normalRailMarker.lowerBound)
        let failedPrefix = String(stageRail[..<normalRailMarker.lowerBound]).lowercased()
        #expect(failedPrefix.contains("stopped") || failedPrefix.contains("blocked"))
        #expect(failedPrefix.contains("accessibilitylabel"))
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
        #expect(
            phaseTitle.contains("case .failed: return \"Capture stopped\"")
                || phaseTitle.contains("case .failed: return \"Capture blocked\"")
        )
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
