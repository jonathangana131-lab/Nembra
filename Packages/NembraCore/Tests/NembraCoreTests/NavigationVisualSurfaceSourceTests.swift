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
