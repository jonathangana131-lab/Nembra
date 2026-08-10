import Foundation
import Testing

@Suite("Home accessibility control layout source")
struct HomeAccessibilityControlLayoutSourceTests {
    @Test("Accessibility Dynamic Type does not keep Home action controls in a fixed horizontal strip")
    func adaptiveActionControls() throws {
        let source = try String(contentsOf: homeViewURL, encoding: .utf8)

        #expect(source.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("VStack(spacing: 12)"))
        #expect(!source.contains("Text(available ? subtitle : \"Unavailable\")\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                        .lineLimit(1)"))
        #expect(!source.contains(".frame(height: 58)\n            .frame(maxWidth: .infinity)"))
    }

    private var homeViewURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    }
}
