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
    #expect(source.contains("home.metric.duration"))
    #expect(source.contains("home.horizon-entry"))
    #expect(source.contains("home.mode.selector"))
    #expect(source.contains("batteryAccessibilityValue"))
    #expect(source.contains("parts.append(\"low battery\")"))

    let statusPanelStart = try #require(source.range(of: "private var readinessAndToday: some View"))
    let controlsStart = try #require(source.range(of: "private var controlsRail: some View", range: statusPanelStart.upperBound..<source.endIndex))
    let statusPanel = String(source[statusPanelStart.lowerBound..<controlsStart.lowerBound])

    #expect(statusPanel.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(statusPanel.contains("VStack(alignment: .leading, spacing: 18)"))
    #expect(statusPanel.contains("HStack(alignment: .top, spacing: 20)"))
    #expect(statusPanel.contains("Divider()"))
    #expect(statusPanel.contains(".fixedSize(horizontal: false, vertical: true)"))
    #expect(statusPanel.contains(".accessibilityIdentifier(\"home.horizon-entry\")"))

    let headerStart = try #require(source.range(of: "private var vehicleHeader: some View"))
    let panelStart = try #require(source.range(of: "private var energyHero: some View", range: headerStart.upperBound..<source.endIndex))
    let header = String(source[headerStart.lowerBound..<panelStart.lowerBound])
    #expect(header.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(header.contains("VStack(alignment: .leading, spacing: 16)"))

    let recoveryStart = try #require(source.range(of: "private var connectionRecovery: some View"))
    let recoveryEnd = try #require(source.range(of: "private enum ConnectionRecoveryAction", range: recoveryStart.upperBound..<source.endIndex))
    let recovery = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
    #expect(recovery.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(recovery.contains(".frame(minWidth: 44, minHeight: 44)"))
    #expect(recovery.contains(".accessibilityHidden(true)"))
}
