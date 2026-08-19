import Foundation
import Testing

@Suite("Vehicle Controls visual closure")
struct VehicleControlsVisualClosureSourceTests {
    @Test("Compact portrait choices do not force narrow adaptive columns")
    func compactPortraitUsesNaturalWidthChoiceLayout() throws {
        let source = try vehicleControlsSection()

        #expect(!source.contains("GridItem(.adaptive(minimum: 128)"))
        #expect(source.contains("GridItem(.flexible(), spacing: 10)"))
    }

    @Test("Vehicle Controls uses native navigation and safe-area-aware tab clearance")
    func usesNativeNavigationAndTabClearance() throws {
        let source = try vehicleControlsSection()

        #expect(source.contains("ScrollView"))
        #expect(source.contains("LazyVStack(alignment: .leading"))
        #expect(source.contains(".safeAreaPadding(.bottom, tabBarClearance)"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize ? 104 : 80"))
        #expect(source.contains(".navigationTitle(\"Vehicle\")"))
        #expect(!source.contains("persistentNavigationViewportClearance"))
    }

    @Test("Truth and interaction geometry remain preserved")
    func preservesTruthAndTargets() throws {
        let source = try vehicleControlsSection()

        #expect(source.contains("vehicle.canLockFromCurrentSpeedEvidence"))
        #expect(source.contains("capabilities.hasUserFacingSpeedLimitMapping"))
        #expect(source.contains("Last confirmed settings shown below"))
        #expect(source.contains("Last confirmed selection"))
        #expect(source.contains("vehicle.batteryDisplayPercent"))
        #expect(source.contains("Estimated range unavailable, not calibrated."))
        #expect(source.contains("minHeight: 58"))
        #expect(source.contains("minHeight: 44"))
    }

    private func vehicleControlsSection() throws -> Substring {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        guard let start = source.range(of: "struct VehicleControlsView: View"),
              let end = source.range(of: "/// Product-facing Battery/Range surface.", range: start.upperBound..<source.endIndex) else {
            Issue.record("VehicleControlsView source section was not found")
            throw SourceContractError.sectionMissing
        }
        return source[start.lowerBound..<end.lowerBound]
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
