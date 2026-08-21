import Foundation
import Testing

@Suite("Nembra glass disabled affordance")
struct NembraGlassDisabledAffordanceSourceTests {
    @Test("Shared glass controls visibly distinguish disabled state")
    func disabledControlsAreVisuallyDistinct() throws {
        let source = try readRepositoryFile("NembraApp/DesignSystem/NembraVisuals.swift")

        #expect(source.contains("private var disabledOpacity: Double"))
        #expect(source.contains(".opacity(isEnabled ? 1 : disabledOpacity)"))
        #expect(source.contains("colorSchemeContrast == .increased ? 0.72 : 0.58"))
    }

    @Test("Disabled appearance does not restore Liquid Glass interactivity")
    func disabledGlassStaysNonInteractive() throws {
        let source = try readRepositoryFile("NembraApp/DesignSystem/NembraVisuals.swift")

        #expect(source.contains(".regular.interactive(isEnabled)"))
        #expect(source.contains("@Environment(\\.isEnabled) private var isEnabled"))
    }

    @Test("Opaque accessibility fallback retains an explicit control boundary")
    func reduceTransparencyKeepsBoundary() throws {
        let source = try readRepositoryFile("NembraApp/DesignSystem/NembraVisuals.swift")

        #expect(source.contains("reduceTransparency || showBorders"))
        #expect(source.contains("Color(uiColor: .secondarySystemBackground)"))
        #expect(source.contains(".strokeBorder("))
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
