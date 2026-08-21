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

    @Test("Shipping Home quick controls consume the shared disabled affordance")
    func homeQuickControlsUseSharedGlassStyle() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/HomeView.swift")
        guard let start = source.range(of: "private func actionControl("),
              let end = source.range(of: "// MARK: - Ride mode", range: start.upperBound..<source.endIndex) else {
            Issue.record("Home actionControl source section was not found")
            throw SourceContractError.sectionMissing
        }

        let actionControl = source[start.lowerBound..<end.lowerBound]
        guard let glass = actionControl.range(of: ".nembraGlassControl()"),
              let disabled = actionControl.range(of: ".disabled(") else {
            Issue.record("Home quick controls are no longer wired through shared glass disabled styling")
            throw SourceContractError.sectionMissing
        }

        #expect(glass.lowerBound < disabled.lowerBound)
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

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
