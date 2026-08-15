import Foundation
import Testing

@Suite("Battery/Range accessibility launcher clearance")
struct BatteryRangeAccessibilityLauncherClearanceSourceTests {
    @Test("Accessibility Battery/Range reserves the expanded Navigation launcher from the viewport")
    func accessibilityViewportClearsExpandedNavigationLauncher() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try batteryRangeViewSection(in: source)

        #expect(view.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(view.contains("persistentNavigationViewportClearance"))
        #expect(view.contains(".padding(.bottom, persistentNavigationViewportClearance)"))
        #expect(view.contains("? 144 : 72"))
    }

    @Test("Clearance is viewport geometry, not another content-tail spacer")
    func clearanceDoesNotHideInsideScrollContent() throws {
        let source = try readRepositoryFile("NembraApp/Features/Home/VehicleControlsView.swift")
        let view = try batteryRangeViewSection(in: source)

        guard let contentTail = view.range(of: ".safeAreaPadding(.bottom, 36)"),
              let viewportModifier = view.range(
                of: "\n        }\n        .padding(.bottom, persistentNavigationViewportClearance)"
              ) else {
            Issue.record("BatteryRangeView viewport-clearance boundary was not found")
            throw SourceContractError.sectionMissing
        }

        #expect(contentTail.upperBound < viewportModifier.lowerBound)
    }

    private func batteryRangeViewSection(in source: String) throws -> Substring {
        guard let start = source.range(of: "private struct BatteryRangeView: View"),
              let end = source.range(of: "private var batteryHero: some View", range: start.upperBound..<source.endIndex) else {
            Issue.record("BatteryRangeView body section was not found")
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
