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
    #expect(standardHero.contains("HomeHeroLayout.scooterWidthFraction"))
    #expect(standardHero.contains("HomeHeroLayout.scooterMaximumSize"))
    #expect(standardHero.contains("HomeHeroLayout.batteryHeight"))
    #expect(standardHero.contains("HomeHeroLayout.batteryTop"))
    #expect(standardHero.contains("HomeHeroLayout.scooterCenterXFraction"))
    #expect(standardHero.contains("HomeHeroLayout.scooterCenterY"))
    #expect(standardHero.contains("HomeHeroLayout.standardHeight"))
    #expect(standardHero.contains("HomeHeroGroundingScene(layout: .standard)"))
    #expect(standardHero.contains(".equatable()"))
    #expect(standardHero.contains(".clipped()"))
    #expect(accessibilityHero.contains("HomeHeroGroundingScene(layout: .accessibility)"))
    #expect(accessibilityHero.contains(".equatable()"))
    #expect(energyHero.contains("if usesStackedEnergyHeroLayout"))
    #expect(source.contains("dynamicTypeSize.isAccessibilitySize || batteryNumericFontSize > 68"))
    #expect(source.contains("@ScaledMetric(relativeTo: .largeTitle) private var batteryNumericFontSize"))
    #expect(source.contains("@ScaledMetric(relativeTo: .title2) private var batteryPercentFontSize"))

    // The selected Home hero preserves a named copy-safe zone rather than
    // allowing the temporary scooter silhouette to cross battery text.
    #expect(source.contains("static let batteryCopySafeWidth"))
    #expect(source.contains("HomeHeroLayout.batteryCopySafeWidth"))
    #expect(source.contains("static let scooterCenterXFraction"))
    #expect(source.contains("static let batteryNumericSafeWidth: CGFloat = 120"))
    #expect(source.contains("static let batteryCopySafeWidth: CGFloat = 108"))
    #expect(source.contains("static let scooterWidthFraction: CGFloat = 0.80"))
    #expect(source.contains("static let scooterMaximumSize: CGFloat = 278"))
    #expect(source.contains("static let scooterCenterXFraction: CGFloat = 0.65"))

    // iPhone 12 supplies a 390-point portrait window and Home takes 20 points
    // per side. These conservative row-specific alpha bounds were measured on
    // the documented temporary 500px ES80 source: x=97 in the numeric band and
    // x=110 in the battery-copy band. Keep at least 20 points of separation.
    let contentWidth = 390.0 - 40.0
    let scooterSize = min(contentWidth * 0.80, 278.0)
    let scooterOriginX = contentWidth * 0.65 - scooterSize / 2
    let numericSpriteMinX = scooterOriginX + scooterSize * (97.0 / 500.0)
    let batterySpriteMinX = scooterOriginX + scooterSize * (110.0 / 500.0)
    #expect(numericSpriteMinX - 120.0 >= 20.0)
    #expect(batterySpriteMinX - (16.0 + 108.0) >= 20.0)

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
    #expect(source.contains(".padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 5)"))
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
    #expect(header.contains("NembraColor.primaryText.opacity(0.44)"))
    #expect(header.contains(".accessibilityHidden(true)"))

    let batteryReadoutEnd = try #require(
        source.range(
            of: "private var batteryBody: some View",
            range: batteryReadoutStart.upperBound..<source.endIndex
        )
    )
    let batteryReadout = String(
        source[batteryReadoutStart.lowerBound..<batteryReadoutEnd.lowerBound]
    )
    #expect(
        batteryReadout.components(separatedBy: ".foregroundStyle(batteryValueColor)").count == 3
    )
    #expect(!batteryReadout.contains("batteryValueColor.opacity"))
    #expect(source.contains("Color(red: 1.00, green: 0.36, blue: 0.32)"))
    #expect(source.contains("case (true, .percentage), (true, .estimatedRange):"))
    #expect(source.contains("NembraColor.primaryText.opacity(0.82)"))
    #expect(!source.contains("NembraColor.secondaryText.opacity(batteryIsRetained"))

    let recoveryStart = try #require(source.range(of: "private var connectionRecovery: some View"))
    let recoveryEnd = try #require(source.range(of: "private enum ConnectionRecoveryAction", range: recoveryStart.upperBound..<source.endIndex))
    let recovery = String(source[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
    #expect(recovery.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(recovery.contains(".frame(minWidth: 44, minHeight: 44)"))
    #expect(recovery.contains(".accessibilityHidden(true)"))
}

@Test("Home energy material retains truth and has no perpetual schedule")
func homeEnergyMaterialRetainsSemanticAndScheduleBoundaries() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraApp/Features/Home/HomeView.swift"),
        encoding: .utf8
    )

    let batteryBodyStart = try #require(source.range(of: "private var batteryBody: some View"))
    let rangeCopyStart = try #require(
        source.range(
            of: "private func batteryRangeCopy(",
            range: batteryBodyStart.upperBound..<source.endIndex
        )
    )
    let readinessStart = try #require(
        source.range(
            of: "// MARK: - Readiness and durable Today",
            range: rangeCopyStart.upperBound..<source.endIndex
        )
    )
    let batteryBody = String(source[batteryBodyStart.lowerBound..<rangeCopyStart.lowerBound])
    let rangeCopy = String(source[rangeCopyStart.lowerBound..<readinessStart.lowerBound])

    #expect(batteryBody.contains("HomeBatteryMaterial("))
    #expect(batteryBody.contains("fillFraction: CGFloat(batteryFillFraction)"))
    #expect(batteryBody.contains("isLowBattery: isBatteryLow"))
    #expect(batteryBody.contains("batteryRangePrimaryColor"))
    #expect(batteryBody.contains("batteryRangeSecondaryColor"))
    #expect(!batteryBody.contains(".mask"))
    #expect(rangeCopy.contains("HomeHeroLayout.batteryCopySafeWidth"))
    #expect(
        rangeCopy.contains(
            ".font(.system(.headline, design: .rounded, weight: batteryRangePrimaryWeight))"
        )
    )
    #expect(rangeCopy.contains(".font(.caption.weight(.regular))"))

    let materialStart = try #require(
        source.range(of: "private struct HomeBatteryMaterial: View, @MainActor Animatable")
    )
    let groundingStart = try #require(
        source.range(
            of: "private struct HomeHeroGroundingScene: View",
            range: materialStart.upperBound..<source.endIndex
        )
    )
    let glassStart = try #require(
        source.range(
            of: "private struct HomeControlIconGlassModifier: ViewModifier",
            range: groundingStart.upperBound..<source.endIndex
        )
    )
    let material = String(source[materialStart.lowerBound..<groundingStart.lowerBound])
    let grounding = String(source[groundingStart.lowerBound..<glassStart.lowerBound])

    // The battery is a passive Canvas with a bounded SOC animation input. It
    // must never gain a TimelineView, display link, or glass material.
    #expect(material.contains("Canvas(opaque: false, rendersAsynchronously: false)"))
    #expect(material.contains("var animatableData: CGFloat"))
    #expect(material.contains("private static let chargeRibSpacing: CGFloat = 4"))
    #expect(material.contains("by: Self.chargeRibSpacing"))
    #expect(material.contains("chargeContext.clip(to: fillPath)"))
    #expect(material.contains("HomeHeroLayout.batteryCopySafeWidth + 34"))
    #expect(material.contains("copyWellRect.minX + fullCopyWellWidth"))
    #expect(material.contains("location: 0.84"))
    #expect(material.contains("copyWellPath"))
    #expect(material.contains("reservoirPath"))
    #expect(material.contains("terminalPath"))
    #expect(material.contains("shoulderPath"))
    #expect(material.contains("isLowBattery ? .red : NembraColor.gold"))
    #expect(material.contains("guard fillFraction > 0 else { return 0 }"))
    #expect(!material.contains("TimelineView"))
    #expect(!material.contains("glassEffect"))

    // Grounding is likewise one static Canvas, with separate semantic layers
    // for physical contact instead of one pasted-on oval.
    #expect(grounding.contains("Canvas(opaque: false, rendersAsynchronously: false)"))
    #expect(grounding.contains("View, @MainActor Equatable"))
    #expect(grounding.contains("softContext.addFilter(.blur"))
    for layerName in [
        "ambientShadow",
        "deckShadow",
        "frontTireContact",
        "rearTireContact",
        "goldPool",
        "floorTop"
    ] {
        #expect(grounding.contains(layerName))
    }
    #expect(!grounding.contains("TimelineView"))

    let continuationStart = try #require(
        source.range(of: "private var latestRideContinuation: some View")
    )
    let continuationLabelStart = try #require(
        source.range(
            of: "private func latestRideLabel(",
            range: continuationStart.upperBound..<source.endIndex
        )
    )
    let continuation = String(source[continuationStart.lowerBound..<continuationLabelStart.lowerBound])
    #expect(continuation.contains(".nembraGlassControl()"))
}

@Test("Home UI tests retain standard audits and Accessibility XXXL runtime evidence")
func homeRuntimeAccessibilityCoverageRemainsProductionStrength() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraUITests/NembraUITests.swift"),
        encoding: .utf8
    )

    let auditStart = try #require(
        source.range(of: "func testConnectedHomePassesProductionAccessibilityAudit() throws")
    )
    let accessibilityXXXLStart = try #require(
        source.range(
            of: "func testConnectedHomeAtAccessibilityXXXLKeepsTruthAndControlsReachable()",
            range: auditStart.upperBound..<source.endIndex
        )
    )
    let nextTestStart = try #require(
        source.range(
            of: "func testUnavailableScooterCanRecoverWithoutInventingLiveState()",
            range: accessibilityXXXLStart.upperBound..<source.endIndex
        )
    )
    let audit = String(source[auditStart.lowerBound..<accessibilityXXXLStart.lowerBound])
    let accessibilityXXXL = String(
        source[accessibilityXXXLStart.lowerBound..<nextTestStart.lowerBound]
    )

    #expect(audit.contains("launch(scenario: \"connected-stopped\", orientation: .portrait)"))
    #expect(audit.contains("performAccessibilityAudit"))
    #expect(audit.contains("assertMinimumTouchTarget(vehicleControls"))
    for auditType in [
        ".sufficientElementDescription",
        ".hitRegion",
        ".contrast",
        ".textClipped",
        ".trait",
        ".dynamicType"
    ] {
        #expect(audit.contains(auditType))
    }

    #expect(accessibilityXXXL.contains("\"-UIPreferredContentSizeCategoryName\""))
    #expect(
        accessibilityXXXL.contains(
            "\"UICTContentSizeCategoryAccessibilityXXXL\""
        )
    )
    for stableIdentifier in [
        "home.connection-status",
        "home.metric.battery",
        "home.horizon-entry",
        "home.mode.selector",
        "home.latest-ride.empty"
    ] {
        #expect(accessibilityXXXL.contains(stableIdentifier))
    }
    for requiredSemantic in [
        "SIM, QA only, synthetic evidence",
        "92 percent",
        "no learned range",
        "Automatic ride tracking",
        "Vehicle: Connected",
        "Light, Off",
        "Lock, Ready",
        "No completed rides yet",
        "safely saved"
    ] {
        #expect(accessibilityXXXL.contains(requiredSemantic))
    }
    #expect(accessibilityXXXL.contains("assertMinimumTouchTarget"))
    #expect(accessibilityXXXL.contains("scrollFullyInsideWindowAndAboveTabBar"))
    #expect(
        accessibilityXXXL.contains(
            "Home Accessibility XXXL Top - Simulator QA Only"
        )
    )
    #expect(
        accessibilityXXXL.contains(
            "Home Accessibility XXXL Bottom - Simulator QA Only"
        )
    )
    #expect(source.contains("app.launchArguments.append(contentsOf: arguments)"))
    #expect(source.contains("private func scrollFullyInsideWindowAndAboveTabBar("))
    #expect(
        source.components(separatedBy: "performAccessibilityAudit(for: [.contrast])").count >= 3,
        "Retained and low-battery fixtures must both keep state-specific contrast audits."
    )
}
