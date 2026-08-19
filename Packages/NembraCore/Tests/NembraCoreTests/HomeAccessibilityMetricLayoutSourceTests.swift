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
    #expect(source.contains("home.battery.retained-freshness"))
    #expect(source.contains("Text(\"Last confirmed\")"))
    #expect(source.contains("vehicle.retainedBatteryObservedAt"))
    #expect(source.contains("Text(observedAt, style: .relative)"))
    #expect(source.contains(".formatted(date: .complete, time: .shortened)"))
    #expect(source.contains("home.battery.low-warning"))
    #expect(source.contains("Label(\"Low battery\", systemImage: \"exclamationmark.triangle.fill\")"))
    #expect(source.contains("batteryAccessibilityValue"))
    #expect(source.contains("parts.append(\"low battery\")"))

    // Home keeps the selected simultaneous percentage + range composition, but
    // the whole energy instrument is one native control whose emphasis follows
    // the same persisted presentation state as Horizon. Numeric range remains
    // fenced behind the owner-bound adaptive-range presentation policy.
    #expect(source.contains("Button {"))
    #expect(source.contains("cockpit.toggleBatteryPrimaryReadout()"))
    #expect(source.contains(".buttonStyle(.plain)"))
    #expect(source.contains("AdaptiveBatteryRangePrimaryPresentationPolicy()"))
    #expect(source.contains(".resolve(liveEstimate: adaptiveRangeEstimate)"))
    #expect(source.contains("batteryPresentation.batteryFillPercent"))
    #expect(source.contains("Both values remain visible"))
    #expect(source.contains("The battery fill always represents state of charge"))
    #expect(!source.contains("advertised"))

    let standardHeroStart = try #require(source.range(of: "private var standardEnergyHero: some View"))
    let accessibilityHeroStart = try #require(
        source.range(
            of: "private var accessibilityEnergyHero: some View",
            range: standardHeroStart.upperBound..<source.endIndex
        )
    )
    let batteryReadoutStart = try #require(
        source.range(
            of: "private var batteryReadout: some View",
            range: accessibilityHeroStart.upperBound..<source.endIndex
        )
    )
    let standardHero = String(source[standardHeroStart.lowerBound..<accessibilityHeroStart.lowerBound])
    let accessibilityHero = String(source[accessibilityHeroStart.lowerBound..<batteryReadoutStart.lowerBound])
    for hero in [standardHero, accessibilityHero] {
        #expect(hero.contains("batteryReadout"))
        #expect(hero.contains("batteryBody"))
    }

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
