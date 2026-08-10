import Foundation
import Testing

@Suite("Navigation visual surface source")
struct NavigationVisualSurfaceSourceTests {
    @Test("Portrait shell exposes a truth-preserving Navigation surface")
    func navigationSurfaceExistsWithoutInventedTelemetry() throws {
        let source = try String(contentsOf: appRootViewURL, encoding: .utf8)

        #expect(source.contains("Label(\"Navigation\", systemImage:" ) || source.contains("Label(\"Navigation\", systemImage: "))
        #expect(source.contains("navigation.surface"))
        #expect(source.contains("Navigation unavailable"))
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("accessibilityReduceMotion"))
        #expect(source.contains("accessibilityReduceTransparency"))

        // Until provider-backed route truth is wired, the shipping surface must
        // not manufacture route distance, ETA, battery impact, speed, or range.
        #expect(!source.contains("navigation.fake"))
        #expect(!source.contains("manufacturerRange"))
        #expect(!source.contains("batteryPercent *"))
    }

    private var appRootViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/App/AppRootView.swift")
    }
}
