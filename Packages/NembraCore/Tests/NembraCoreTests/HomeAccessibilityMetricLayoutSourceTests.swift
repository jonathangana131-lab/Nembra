import Foundation
import Testing

@Test("Home status metrics reflow at Accessibility Dynamic Type")
func homeStatusMetricsReflowAtAccessibilityDynamicType() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
    #expect(source.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(source.contains("home.metric.battery"))
    #expect(source.contains("home.metric.trip"))
    #expect(source.contains("home.metric.mode"))

    let statusPanelStart = try #require(source.range(of: "private var statusPanel: some View"))
    let controlsStart = try #require(source.range(of: "private var controlsSection: some View", range: statusPanelStart.upperBound..<source.endIndex))
    let statusPanel = String(source[statusPanelStart.lowerBound..<controlsStart.lowerBound])

    #expect(statusPanel.contains("VStack(alignment: .leading"))
    #expect(statusPanel.contains("Divider()"))
}
