import Foundation
import Testing

@Suite("Vehicle Controls persistent Navigation footprint")
struct VehicleControlsPersistentNavigationFootprintSourceTests {
    @Test("Vehicle Controls reserves the full portrait launcher footprint from the visible viewport")
    func viewportClearsLauncherFootprint() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try vehicleControlsSection(in: source)

        #expect(view.contains("persistentNavigationViewportClearance"))
        #expect(view.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(view.contains("? 220 : 164"))
        #expect(view.contains(".padding(.bottom, persistentNavigationViewportClearance)"))
    }

    @Test("Launcher clearance stays outside ScrollView content")
    func clearanceIsViewportGeometry() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try vehicleControlsSection(in: source)

        guard let contentTail = view.range(of: ".padding(.bottom, 40)"),
              let viewportModifier = view.range(
                of: "\n        }\n        .padding(.bottom, persistentNavigationViewportClearance)"
              ) else {
            Issue.record("Vehicle Controls viewport-clearance boundary was not found")
            throw SourceContractError.sectionMissing
        }

        #expect(contentTail.upperBound <= viewportModifier.lowerBound)
    }

    @Test("The global Navigation launcher remains untouched")
    func doesNotSolveLocalOverlapByChangingGlobalLauncher() throws {
        let navigationSource = try readRepositoryFile("NembraApp/App/NembraApp.swift")

        #expect(navigationSource.contains(".frame(minWidth: 54, minHeight: 54)"))
        #expect(navigationSource.contains(".padding(.trailing, verticalSizeClass == .compact ? 0 : 18)"))
        #expect(navigationSource.contains(".padding(.bottom, verticalSizeClass == .compact ? 0 : 92)"))
    }

    private func vehicleControlsSection(in source: String) throws -> Substring {
        guard let start = source.range(of: "struct VehicleControlsView: View"),
              let end = source.range(of: "private struct BatteryRangeView: View", range: start.upperBound..<source.endIndex) else {
            Issue.record("VehicleControlsView section was not found")
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
