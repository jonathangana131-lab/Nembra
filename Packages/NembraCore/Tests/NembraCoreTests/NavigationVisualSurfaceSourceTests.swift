import Foundation
import Testing

@Suite("Navigation visual surface source")
struct NavigationVisualSurfaceSourceTests {
    @Test("Shipping host exposes a truth-preserving Navigation surface")
    func navigationSurfaceExistsWithoutInventedTelemetry() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)

        #expect(source.contains("navigation.surface"))
        #expect(source.contains("Navigation unavailable"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(source.contains("accessibilityReduceTransparency"))
        #expect(source.contains("Search for a place or address. Nembra will preview it here without using scooter telemetry."))
        #expect(source.contains("Map results stay separate from scooter telemetry."))

        #expect(!source.contains("navigation.fake"))
        #expect(!source.contains("manufacturerRange"))
        #expect(!source.contains("batteryPercent *"))
    }

    @Test("Accessibility-size Navigation states recompose instead of clipping")
    func accessibilityLowerSurfaceUsesDedicatedScrollableComposition() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let emptyState = slice(
            source,
            after: "private var navigationEmptyState: some View {",
            before: "private func navigationStatusSurface("
        )
        let statusState = slice(
            source,
            after: "private func navigationStatusSurface(",
            before: "private var recentDestinationList"
        )

        #expect(emptyState.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(emptyState.contains("ScrollView"))
        #expect(emptyState.contains(".title2.weight(.semibold)"))
        #expect(statusState.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(statusState.contains("ScrollView"))
    }

    @Test("Map and launcher preserve accessibility geometry")
    func accessibilityGeometryIsExplicit() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        #expect(source.contains(".frame(minWidth: 54, minHeight: 54)"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize ? 160 : 180"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize ? 220 : 280"))
        #expect(source.contains("withAnimation(reduceMotion ? nil : .snappy(duration: 0.28))"))
        #expect(source.contains("if reduceTransparency"))
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
