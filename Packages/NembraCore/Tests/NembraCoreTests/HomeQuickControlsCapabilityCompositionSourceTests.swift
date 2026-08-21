import Foundation
import Testing

@Suite("Home quick controls capability composition")
struct HomeQuickControlsCapabilityCompositionSourceTests {
    @Test("Home omits the quick-controls shell when no quick command capability is authorized")
    func homeOmitsEmptyQuickControlsShell() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/HomeView.swift")
        let lines = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard let mountIndex = lines.firstIndex(of: "if hasQuickControls {") else {
            Issue.record("Home does not capability-gate the quick-controls mount")
            return
        }

        #expect(lines.indices.contains(mountIndex + 2))
        if lines.indices.contains(mountIndex + 2) {
            #expect(lines[mountIndex + 1] == "controlsSection")
            #expect(lines[mountIndex + 2] == "}")
        }

        #expect(source.contains("private var hasQuickControls: Bool"))
        #expect(source.contains("let capabilities = vehicle.profile.capabilities"))
        #expect(source.contains("return capabilities.supportsHeadlight || capabilities.supportsLock"))
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }
}
