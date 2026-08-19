import Foundation
import Testing

@Suite("Vehicle Controls native navigation footprint")
struct VehicleControlsPersistentNavigationFootprintSourceTests {
    @Test("Vehicle Controls clears the native floating tab bar with safe-area content geometry")
    func contentClearsNativeTabBar() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try vehicleControlsSection(in: source)

        #expect(view.contains(".safeAreaPadding(.bottom, tabBarClearance)"))
        #expect(view.contains("dynamicTypeSize.isAccessibilitySize ? 104 : 80"))
        #expect(!view.contains("persistentNavigationViewportClearance"))
        #expect(!view.contains("launcher"))
    }

    @Test("Vehicle remains a native TabView destination with its own NavigationStack")
    func vehicleUsesNativeTabAndNavigationStack() throws {
        let source = try readRepositoryFile("NembraApp/App/AppRootView.swift")

        #expect(source.contains("TabView(selection: $selectedTab)"))
        #expect(source.contains("NavigationStack {\n                VehicleControlsView()"))
        #expect(source.contains("Label(\"Vehicle\", systemImage: \"scooter\")"))
        #expect(source.contains(".tag(NembraPrimaryTab.vehicle)"))
    }

    @Test("Navigation uses a native sheet instead of a floating global launcher")
    func navigationUsesNativeSheetPresentation() throws {
        let navigationSource = try readRepositoryFile("NembraApp/App/NembraApp.swift")

        #expect(navigationSource.contains(".sheet(isPresented: $isNavigationPresented)"))
        #expect(navigationSource.contains("NavigationStack {\n                NembraNavigationView()"))
        #expect(!navigationSource.contains(".frame(minWidth: 54, minHeight: 54)"))
        #expect(!navigationSource.contains("persistentNavigationViewportClearance"))
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
