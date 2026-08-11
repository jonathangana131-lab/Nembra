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

    @Test("Landscape Navigation entry reuses qualified stopped-speed authority")
    func landscapeLauncherFailsClosedWithoutQualifiedStoppedSpeed() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let host = slice(
            source,
            after: "private struct NembraNavigationHost<Content: View>: View {",
            before: "private struct NembraRecentDestination"
        )
        let launcherPolicy = slice(
            host,
            after: "private var shouldShowNavigationLauncher: Bool {",
            before: "private var launcherAlignment"
        )

        #expect(host.contains("@Environment(VehicleStore.self) private var vehicle"))
        #expect(launcherPolicy.contains("guard verticalSizeClass == .compact else { return true }"))
        #expect(launcherPolicy.contains("vehicle.simulatorQualifiedLiveSpeedKilometersPerHour"))
        #expect(launcherPolicy.contains("return speed < 0.5"))
        #expect(host.contains("verticalSizeClass == .compact ? .top : .bottomTrailing"))
        #expect(host.contains("Available while current stopped speed is confirmed"))
    }

    @Test("Accessibility Dynamic Type has dedicated launch and map geometry")
    func accessibilityDynamicTypeRecomposesNavigationGeometry() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let host = slice(
            source,
            after: "private struct NembraNavigationHost<Content: View>: View {",
            before: "private struct NembraRecentDestination"
        )
        let navigation = slice(
            source,
            after: "private struct NembraNavigationView: View {",
            before: "@MainActor\n    private func searchDestinations()"
        )

        // Merely reading Dynamic Type is not enough. Accessibility sizes must
        // switch the icon-only launcher to labeled geometry while preserving a
        // large touch target, and map height must deliberately recompose for both
        // portrait and compact landscape rather than stretching portrait.
        #expect(host.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(host.contains("Label(\"Navigation\", systemImage: \"location.north.circle.fill\")"))
        #expect(host.contains(".frame(minWidth: 54, minHeight: 54)"))
        #expect(navigation.contains("private var navigationMapHeight: CGFloat"))
        #expect(navigation.contains("if verticalSizeClass == .compact"))
        #expect(navigation.contains("dynamicTypeSize.isAccessibilitySize ? 160 : 180"))
        #expect(navigation.contains("dynamicTypeSize.isAccessibilitySize ? 220 : 280"))
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

        // Large text is a separate composition, not a scaled-up copy of the
        // decorative default state. It must be able to scroll if text wraps beyond
        // the available lower sheet while keeping semantic title/detail content.
        #expect(emptyState.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(emptyState.contains("ScrollView"))
        #expect(emptyState.contains(".title2.weight(.semibold)"))
        #expect(statusState.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(statusState.contains("ScrollView"))
    }

    @Test("Empty and failure states use the Nembra Navigation hierarchy")
    func importantNavigationStatesAvoidStockUnavailableCards() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let navigation = slice(
            source,
            after: "private struct NembraNavigationView: View {",
            before: "@MainActor\n    private func searchDestinations()"
        )

        #expect(!navigation.contains("ContentUnavailableView"))
        #expect(navigation.contains("private var navigationEmptyState: some View"))
        #expect(navigation.contains("private func navigationStatusSurface("))
        #expect(navigation.contains("Text(\"NAVIGATION\")"))
        #expect(navigation.contains("Text(\"Find a destination\")"))
        #expect(navigation.contains("Search for a place or address. Nembra will preview it here without using scooter telemetry."))
        #expect(navigation.contains("Choose a destination before riding."))
        #expect(navigation.contains("No destination found"))
        #expect(navigation.contains("Map results stay separate from scooter telemetry."))
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
            before: "private var navigationMapHeight"
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

    @Test("Reduce Motion gates Navigation presentation animation")
    func reduceMotionRemovesForcedNavigationAnimation() throws {
        let source = try String(contentsOf: nembraAppURL, encoding: .utf8)
        let host = slice(
            source,
            after: "private struct NembraNavigationHost<Content: View>: View {",
            before: "private struct NembraRecentDestination"
        )

        // The setting must gate the actual presentation animation. Merely reading
        // accessibilityReduceMotion elsewhere is not an acceptance contract.
        #expect(host.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        #expect(host.contains("withAnimation(reduceMotion ? nil : .snappy(duration: 0.28))"))
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
