import Foundation
import Testing

@Suite("Home quick controls capability composition")
struct HomeQuickControlsCapabilityCompositionSourceTests {
    @Test("Home omits the quick-controls shell when no quick command capability is authorized")
    func homeOmitsEmptyQuickControlsShell() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/HomeView.swift")

        #expect(source.contains("""
                if hasQuickControls {
                    controlsSection
                }
        """))
        #expect(source.contains("""
    private var hasQuickControls: Bool {
        let capabilities = vehicle.profile.capabilities
        return capabilities.supportsHeadlight || capabilities.supportsLock
    }
        """))
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
