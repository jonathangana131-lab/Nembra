import Foundation
import Testing

@Test("Home status and recovery surfaces reflow at Accessibility Dynamic Type")
func homeStatusAndRecoveryReflowAtAccessibilityDynamicType() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = repositoryRoot
        .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let appRootSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraApp/App/AppRootView.swift"),
        encoding: .utf8
    )

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
    #expect(source.contains(".accessibilityLabel(\"Low battery\")"))
    #expect(source.contains("batteryAccessibilityValue"))
    #expect(source.contains("parts.append(\"low battery\")"))
    #expect(!source.contains(".accessibilityIdentifier(\"home.energy-hero\")"))
    #expect(!source.contains(".accessibilityIdentifier(\"home.controls\")"))
    #expect(source.contains("Text(\"SIM · QA\")"))
    #expect(source.contains(".accessibilityIdentifier(\"home.connection-status\")"))
    #expect(source.contains(".accessibilityValue(vehicleStatusAccessibilityValue)"))
    #expect(source.contains("SIM, QA only, synthetic evidence"))
    #expect(!source.contains("Text(\"Nembra Simulator\")"))

    // Automatic-ride state is integrated into the compact Horizon readiness
    // control instead of consuming a second top strip.
    #expect(source.contains("rides.statusText"))
    #expect(source.contains("readinessAccessibilityValue"))
    #expect(!appRootSource.contains("private struct RideStatusStrip"))
    #expect(!appRootSource.contains("home.ride-status"))
    #expect(!appRootSource.contains(".safeAreaInset(edge: .top"))

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
    let energyHeroStart = try #require(source.range(of: "private var energyHero: some View"))
    let energyHero = String(source[energyHeroStart.lowerBound..<standardHeroStart.lowerBound])
    let batteryControlStart = try #require(energyHero.range(of: "Button {"))
    let batteryControl = String(energyHero[batteryControlStart.lowerBound...])
    #expect(batteryControl.contains(".accessibilityIdentifier(\"home.metric.battery\")"))
    #expect(!batteryControl.contains(".accessibilityElement(children: .ignore)"))

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
    #expect(standardHero.contains("min(proxy.size.width * 0.98, 320)"))
    #expect(standardHero.contains(".position(x: proxy.size.width * 0.54, y: 168)"))
    #expect(standardHero.contains(".frame(height: 328)"))

    let statusPanelStart = try #require(source.range(of: "private var readinessAndToday: some View"))
    let controlsStart = try #require(source.range(of: "private var controlsRail: some View", range: statusPanelStart.upperBound..<source.endIndex))
    let statusPanel = String(source[statusPanelStart.lowerBound..<controlsStart.lowerBound])

    #expect(statusPanel.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(statusPanel.contains("spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 7"))
    #expect(statusPanel.contains("VStack(alignment: .leading, spacing: 12)"))
    #expect(statusPanel.contains("HStack(alignment: .top, spacing: 14)"))
    #expect(statusPanel.contains("Divider()"))
    #expect(statusPanel.contains(".fixedSize(horizontal: false, vertical: true)"))
    #expect(statusPanel.contains(".accessibilityIdentifier(\"home.horizon-entry\")"))
    #expect(statusPanel.contains("if let todayEvidenceDetail"))
    #expect(statusPanel.contains(".accessibilityValue(readinessAccessibilityValue)"))
    #expect(!statusPanel.contains("detail: todayDistanceDetail"))
    #expect(!statusPanel.contains("detail: todayDurationDetail"))
    let readinessStart = try #require(statusPanel.range(of: "private var readinessRow: some View"))
    let todayMetricStart = try #require(
        statusPanel.range(
            of: "private func todayMetric(",
            range: readinessStart.upperBound..<statusPanel.endIndex
        )
    )
    let readiness = String(statusPanel[readinessStart.lowerBound..<todayMetricStart.lowerBound])
    #expect(!readiness.contains(".accessibilityElement(children: .ignore)"))

    let headerStart = try #require(source.range(of: "private var vehicleHeader: some View"))
    let panelStart = try #require(source.range(of: "private var energyHero: some View", range: headerStart.upperBound..<source.endIndex))
    let header = String(source[headerStart.lowerBound..<panelStart.lowerBound])
    #expect(header.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(header.contains("VStack(alignment: .leading, spacing: 12)"))

    let recoveryStart = try #require(source.range(of: "private var connectionRecovery: some View"))
    let recoveryEnd = try #require(source.range(of: "private enum ConnectionRecoveryAction", range: recoveryStart.upperBound..<source.endIndex))
    let recovery = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
    #expect(recovery.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(recovery.contains(".frame(minWidth: 44, minHeight: 44)"))
    #expect(recovery.contains(".accessibilityHidden(true)"))
}
