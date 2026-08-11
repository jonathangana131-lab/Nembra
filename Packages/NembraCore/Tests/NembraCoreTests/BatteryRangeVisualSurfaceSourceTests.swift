import Foundation
import Testing

@Suite("Battery/Range app visual truth contract")
struct BatteryRangeVisualSurfaceSourceTests {
    @Test("Battery surface keeps explicit accessibility and motion/contrast adaptations")
    func batterySurfaceAccessibilityContract() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let surface = try batteryRangeSection(in: source)

        #expect(surface.contains("accessibilityIdentifier(\"battery-range.surface\")"))
        #expect(surface.contains("accessibilityIdentifier(\"battery-range.battery\")"))
        #expect(surface.contains("accessibilityReduceMotion"))
        #expect(surface.contains("accessibilityReduceTransparency"))
        #expect(surface.contains("colorSchemeContrast"))
        #expect(surface.contains("dynamicTypeSize"))
        #expect(surface.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(surface.contains("reduceMotion ? .identity : .numericText()"))
    }

    @Test("Range remains visibly unavailable instead of deriving a fake estimate")
    func rangeUnavailableTruthContract() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let surface = try batteryRangeSection(in: source)

        #expect(surface.contains("NOT CALIBRATED"))
        #expect(surface.contains("Text(\"—\")"))
        #expect(surface.contains("never derives"))
        #expect(surface.contains("advertised range"))
        #expect(surface.contains("battery percentage"))
        #expect(surface.contains("guessed efficiency"))
    }

    @Test("Battery presentation exposes one semantic hero instead of gauge-only meaning")
    func batteryHeroSemanticContract() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let surface = try batteryRangeSection(in: source)

        #expect(surface.contains("accessibilityElement(children: .ignore)"))
        #expect(surface.contains("accessibilityLabel(\"Battery\")"))
        #expect(surface.contains("accessibilityValue(batteryAccessibilityValue)"))
        #expect(surface.contains("batterySupportingText"))
        #expect(surface.contains("batteryPrimaryText"))
        #expect(surface.contains("batteryFillFraction"))
    }

    private func batteryRangeSection(in source: String) throws -> Substring {
        guard let start = source.range(of: "/// Product-facing Battery/Range surface.") else {
            Issue.record("BatteryRangeView product surface was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<source.endIndex]
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
