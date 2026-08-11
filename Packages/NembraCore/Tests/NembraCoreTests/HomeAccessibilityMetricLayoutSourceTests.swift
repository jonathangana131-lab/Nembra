import Foundation
import Testing

@Test("Home status and recovery surfaces reflow at Accessibility Dynamic Type")
func homeStatusAndRecoveryReflowAtAccessibilityDynamicType() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
    #expect(source.contains("home.metric.battery"))
    #expect(source.contains("home.metric.trip"))
    #expect(source.contains("home.metric.mode"))
    #expect(source.contains("batteryAccessibilityValue"))
    #expect(source.contains("percent, low battery"))

    let statusPanelStart = try #require(source.range(of: "private var statusPanel: some View"))
    let controlsStart = try #require(source.range(of: "private var controlsSection: some View", range: statusPanelStart.upperBound..<source.endIndex))
    let statusPanel = String(source[statusPanelStart.lowerBound..<controlsStart.lowerBound])

    #expect(statusPanel.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(statusPanel.contains("VStack(spacing: 0)"))
    #expect(statusPanel.contains("Divider()"))
    #expect(statusPanel.contains(".lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)"))
    #expect(statusPanel.contains(".minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)"))

    let headerStart = try #require(source.range(of: "private var vehicleHeader: some View"))
    let panelStart = try #require(source.range(of: "private var statusPanel: some View", range: headerStart.upperBound..<source.endIndex))
    let header = String(source[headerStart.lowerBound..<panelStart.lowerBound])
    #expect(header.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(header.contains("VStack(alignment: .leading, spacing: 12)"))

    let recoveryStart = try #require(source.range(of: "private var connectionRecovery: some View"))
    let recoveryEnd = try #require(source.range(of: "private enum ConnectionRecoveryAction", range: recoveryStart.upperBound..<source.endIndex))
    let recovery = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
    #expect(recovery.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(recovery.contains(".frame(minWidth: 44, minHeight: 44)"))
    #expect(recovery.contains(".accessibilityHidden(true)"))

    let recoveryTextStart = try #require(source.range(of: "private func connectionRecoveryText", range: recoveryStart.upperBound..<recoveryEnd.lowerBound))
    let recoveryActionStart = try #require(source.range(of: "private func connectionRecoveryAction", range: recoveryTextStart.upperBound..<recoveryEnd.lowerBound))
    let recoveryText = String(source[recoveryTextStart.lowerBound..<recoveryActionStart.lowerBound])
    #expect(recoveryText.contains("Text(presentation.title)"))
    #expect(recoveryText.contains("Text(presentation.message)"))
    #expect(!recoveryText.contains("switch presentation.action"))
}
