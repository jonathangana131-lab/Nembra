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

    @Test("Vehicle Controls reserves persistent Navigation from the visible viewport")
    func viewportClearsPersistentNavigation() throws {
        let source = try vehicleControlsSection()

        #expect(source.contains("persistentNavigationViewportClearance"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize ? 220 : 164"))
        #expect(source.contains(".padding(.bottom, persistentNavigationViewportClearance)"))

        guard let scrollEnd = source.range(of: "\n        }\n        .padding(.bottom, persistentNavigationViewportClearance)") else {
            Issue.record("Vehicle Controls viewport-clearance modifier is missing outside ScrollView content")
            throw SourceContractError.sectionMissing
        }
        #expect(scrollEnd.lowerBound > source.startIndex)
    }

    @Test("Truth and interaction geometry remain preserved")
    func preservesTruthAndTargets() throws {
        let source = try vehicleControlsSection()

        #expect(source.contains("vehicle.canLockFromCurrentSpeedEvidence"))
        #expect(source.contains("capabilities.hasUserFacingSpeedLimitMapping"))
        #expect(source.contains("Last confirmed settings shown below"))
        #expect(source.contains("Last confirmed selection"))
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
