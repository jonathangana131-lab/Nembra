import Foundation
import Testing

@Suite("Navigation visual surface source")
struct NavigationVisualSurfaceSourceTests {
    @Test("Shipping host exposes a truth-preserving Navigation surface")
    func navigationSurfaceExistsWithoutInventedTelemetry() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)

        #expect(source.contains("Label(\"Navigation\", systemImage:" ) || source.contains("Label(\"Navigation\", systemImage: "))
        #expect(source.contains("navigation.surface"))
        #expect(source.contains("Navigation unavailable"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(source.contains("accessibilityReduceTransparency"))

        // Both the host launch control and selected-destination overlay must
        // honor Reduce Transparency instead of leaving an isolated Material surface.
        #expect(
            source.components(separatedBy: "@Environment(\\.accessibilityReduceTransparency)").count >= 3
        )
        #expect(source.components(separatedBy: "secondarySystemBackground").count >= 3)

        // Navigation search/preview is MapKit-backed provider truth. It must not
        // manufacture scooter telemetry or convert navigation data into ride truth.
        #expect(!source.contains("navigation.fake"))
        #expect(!source.contains("manufacturerRange"))
        #expect(!source.contains("batteryPercent *"))
    }

    @Test("Accessibility Dynamic Type has dedicated launch and map geometry")
    func accessibilityDynamicTypeRecomposesNavigationGeometry() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let host = slice(
            source,
            after: "private struct NembraNavigationHost<Content: View>: View {",
            before: "private struct NembraRecentDestination"
        )
        let map = slice(
            source,
            after: "private var destinationMap: some View {",
            before: "@ViewBuilder\n    private var searchSurface"
        )

        // Merely reading Dynamic Type is not enough. Accessibility sizes must
        // switch the icon-only launcher to labeled geometry while preserving a
        // large touch target, and the map must deliberately recompose vertically.
        #expect(host.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(host.contains("Label(\"Navigation\", systemImage: \"location.north.circle.fill\")"))
        #expect(host.contains(".frame(minWidth: 54, minHeight: 54)"))
        #expect(map.contains(".frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 220 : 280)"))
    }

    @Test("Reduce Transparency removes Material from both Navigation overlays")
    func reduceTransparencyIsBoundToEachMaterialSurface() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let host = slice(
            source,
            after: "private struct NembraNavigationHost<Content: View>: View {",
            before: "private struct NembraRecentDestination"
        )
        let map = slice(
            source,
            after: "private var destinationMap: some View {",
            before: "@ViewBuilder\n    private var searchSurface"
        )

        // Keep the two contracts scoped independently so a future unrelated
        // secondarySystemBackground elsewhere cannot satisfy this test by count.
        #expect(host.contains("if reduceTransparency"))
        #expect(host.contains("Color(uiColor: .secondarySystemBackground)"))
        #expect(host.contains("Rectangle().fill(.regularMaterial)"))
        #expect(map.contains("if reduceTransparency"))
        #expect(map.contains(".fill(Color(uiColor: .secondarySystemBackground))"))
        #expect(map.contains(".fill(.regularMaterial)"))
    }

    @Test("Changing a query clears stale provider results before debounce")
    func queryChangeCannotPresentPreviousMapKitResults() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let searchFunction = source
            .components(separatedBy: "private func searchDestinations() async {")
            .dropFirst()
            .first ?? ""
        let beforeDebounce = searchFunction
            .components(separatedBy: "try? await Task.sleep(for: .milliseconds(300))")
            .first ?? ""

        // One results clear belongs to the empty-query path; the second must run
        // for non-empty query changes before any debounce or provider request.
        #expect(beforeDebounce.components(separatedBy: "results = []").count >= 3)
        #expect(beforeDebounce.contains("searchError = nil"))
        #expect(beforeDebounce.contains("isSearching = true"))
    }

    private func slice(_ source: String, after start: String, before end: String) -> String {
        let tail = source.components(separatedBy: start).dropFirst().first ?? ""
        return tail.components(separatedBy: end).first ?? ""
    }

    private var nembraAppURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/App/NembraApp.swift")
    }
}
