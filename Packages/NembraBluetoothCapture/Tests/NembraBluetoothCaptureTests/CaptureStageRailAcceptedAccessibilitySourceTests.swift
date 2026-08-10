import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Capture accepted stage-rail accessibility truth")
struct CaptureStageRailAcceptedAccessibilitySourceTests {
    @Test("Accessibility-size accepted rail explicitly announces completion")
    func accessibilitySizeAcceptedRailIsComplete() throws {
        let stageRail = try stageRailSource()
        let accessibilityBranch = String(try section(
            in: stageRail,
            from: "if dynamicTypeSize.isAccessibilitySize",
            to: "} else {"
        ))

        #expect(accessibilityBranch.contains("test.phase == .accepted"))
        #expect(accessibilityBranch.contains("All 4 Capture steps complete, Seal"))
        #expect(accessibilityBranch.contains(".accessibilityLabel("))
        #expect(accessibilityBranch.contains("Step \\(currentStageIndex + 1) of 4, \\(stageLabels[currentStageIndex])"))
    }

    @Test("Standard accepted rail marks every accepted stage complete while preserving pre-acceptance semantics")
    func standardAcceptedSealIsComplete() throws {
        let stageRail = try stageRailSource()
        guard let standardStart = stageRail.range(of: "} else {\n            HStack(spacing: 8) {") else {
            Issue.record("Standard stage rail branch is missing")
            throw SourceContractError.sectionMissing
        }
        let standardBranch = String(stageRail[standardStart.lowerBound...])

        guard let accessibilityLine = standardBranch
            .split(separator: "\n")
            .map(String.init)
            .first(where: { $0.contains(".accessibilityLabel(\"Step") }) else {
            Issue.record("Standard stage accessibility label is missing")
            throw SourceContractError.sectionMissing
        }

        #expect(accessibilityLine.contains("test.phase == .accepted"))
        #expect(accessibilityLine.contains("complete"))
        #expect(accessibilityLine.contains("current"))
        #expect(accessibilityLine.contains("upcoming"))

        #expect(standardBranch.contains("index < currentStageIndex || test.phase == .accepted"))
        #expect(
            accessibilityLine.contains("test.phase == .accepted || index < currentStageIndex")
                || accessibilityLine.contains("index < currentStageIndex || test.phase == .accepted")
        )
    }

    private func stageRailSource() throws -> String {
        let source = try readRepositoryFile("NembraApp/App/NembraCaptureEntrypoint.swift")
        return String(try section(
            in: source,
            from: "private var stageRail: some View",
            to: "private var primarySurface: some View"
        ))
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
