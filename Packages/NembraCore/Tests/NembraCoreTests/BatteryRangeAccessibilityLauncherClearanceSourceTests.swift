import Foundation
import Testing

@Suite("Battery/Range accessibility navigation clearance")
struct BatteryRangeAccessibilityLauncherClearanceSourceTests {
    @Test("Battery/Range reserves native tab-bar safe area at accessibility sizes")
    func accessibilityContentClearsNativeTabBar() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try batteryRangeViewSection(in: source)

        #expect(view.contains("ScrollView"))
        #expect(view.contains(".safeAreaPadding(.bottom, tabBarClearance)"))
        #expect(view.contains("dynamicTypeSize.isAccessibilitySize ? 104 : 80"))
        #expect(view.contains(".navigationTitle(\"Battery & Range\")"))
        #expect(!view.contains("persistentNavigationViewportClearance"))
    }

    @Test("Accessibility Battery/Range recomposes its truthful battery and range readouts")
    func accessibilityReadoutsRecomposeWithoutLauncherGeometry() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try batteryRangeViewSection(in: source)

        #expect(view.contains("ViewThatFits(in: .horizontal)"))
        #expect(view.contains("dynamicTypeSize.isAccessibilitySize ? 52 : 72"))
        #expect(view.contains("dynamicTypeSize.isAccessibilitySize ? 46 : 58"))
        #expect(view.contains(".accessibilityValue(\"Unavailable, not calibrated\")"))
        #expect(!view.contains("padding(.trailing, 72)"))
    }

    private func batteryRangeViewSection(in source: String) throws -> Substring {
        guard let start = source.range(of: "private struct BatteryRangeView: View") else {
            Issue.record("BatteryRangeView section was not found")
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
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return String(decoding: data, as: UTF8.self)
    }

    private enum SourceContractError: Error {
        case sectionMissing
    }
}
