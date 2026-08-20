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
    let homeSourceURL = repositoryRoot
        .appendingPathComponent("NembraApp/Features/Home/HomeView.swift")
    let heroSourceURL = repositoryRoot
        .appendingPathComponent("NembraApp/Features/Home/VehicleHeroView.swift")
    let homeSource = try String(contentsOf: homeSourceURL, encoding: .utf8)
    let heroSource = try String(contentsOf: heroSourceURL, encoding: .utf8)
    let appRootSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraApp/App/AppRootView.swift"),
        encoding: .utf8
    )

    #expect(homeSource.contains("@Environment(\\.dynamicTypeSize) private var dynamicTypeSize"))
    #expect(heroSource.contains("home.metric.battery"))
    #expect(homeSource.contains("home.metric.trip"))
    #expect(homeSource.contains("home.metric.duration"))
    #expect(homeSource.contains("home.horizon-entry"))
    #expect(homeSource.contains("home.mode.selector"))
    #expect(heroSource.contains("home.battery.retained-freshness"))
    #expect(heroSource.contains("Text(\"Last confirmed\")"))
    #expect(heroSource.contains("vehicle.retainedBatteryObservedAt"))
    #expect(heroSource.contains("Text(observedAt, style: .relative)"))
    #expect(heroSource.contains(".formatted(date: .complete, time: .shortened)"))
    #expect(heroSource.contains("home.battery.low-warning"))
    #expect(heroSource.contains("Label(\"Low battery\", systemImage: \"exclamationmark.triangle.fill\")"))
    #expect(heroSource.contains(".accessibilityLabel(\"Low battery\")"))
    #expect(heroSource.contains("batteryAccessibilityValue"))
    #expect(heroSource.contains("parts.append(\"low battery\")"))
    #expect(!heroSource.contains(".accessibilityIdentifier(\"home.energy-hero\")"))
    #expect(!homeSource.contains(".accessibilityIdentifier(\"home.controls\")"))
    #expect(heroSource.contains("Text(\"SIM · QA\")"))
    #expect(heroSource.contains(".accessibilityIdentifier(\"home.connection-status\")"))
    #expect(heroSource.contains(".accessibilityValue(snapshot.status.accessibilityValue)"))
    #expect(heroSource.contains("SIM, QA only, synthetic evidence"))
    #expect(!heroSource.contains("Text(\"Nembra Simulator\")"))

    // Automatic-ride state is integrated into the compact Horizon readiness
    // control instead of consuming a second top strip.
    #expect(homeSource.contains("rides.statusText"))
    #expect(homeSource.contains("readinessAccessibilityValue"))
    #expect(!appRootSource.contains("private struct RideStatusStrip"))
    #expect(!appRootSource.contains("home.ride-status"))
    #expect(!appRootSource.contains(".safeAreaInset(edge: .top"))

    // Home keeps the selected simultaneous percentage + range composition, but
    // the whole energy instrument is one native control whose emphasis follows
    // the same persisted presentation state as Horizon. Numeric range remains
    // fenced behind the owner-bound adaptive-range presentation policy.
    #expect(heroSource.contains("Button {"))
    #expect(heroSource.contains("cockpit.toggleBatteryPrimaryReadout()"))
    #expect(heroSource.contains(".buttonStyle(.plain)"))
    #expect(heroSource.contains("AdaptiveBatteryRangePrimaryPresentationPolicy()"))
    #expect(heroSource.contains(".resolve(liveEstimate: adaptiveRangeEstimate)"))
    #expect(heroSource.contains("batteryPresentation.batteryFillPercent"))
    #expect(heroSource.contains("Both values remain visible"))
    #expect(heroSource.contains("The battery fill always represents state of charge"))
    #expect(!heroSource.contains("advertised"))

    let energyHeroStart = try #require(heroSource.range(of: "struct HomeEnergyHeroBridge: View"))
    let sceneStart = try #require(
        heroSource.range(
            of: "private struct HomeEnergyHeroScene: View, @MainActor Equatable",
            range: energyHeroStart.upperBound..<heroSource.endIndex
        )
    )
    let standardHeroStart = try #require(
        heroSource.range(
            of: "private var standardEnergyHero: some View",
            range: sceneStart.upperBound..<heroSource.endIndex
        )
    )
    let energyHero = String(heroSource[energyHeroStart.lowerBound..<sceneStart.lowerBound])
    let batteryControlStart = try #require(energyHero.range(of: "Button {"))
    let batteryControl = String(energyHero[batteryControlStart.lowerBound...])
    #expect(batteryControl.contains(".accessibilityIdentifier(\"home.metric.battery\")"))
    #expect(!batteryControl.contains(".accessibilityElement(children: .ignore)"))

    let accessibilityHeroStart = try #require(
        heroSource.range(
            of: "private var accessibilityEnergyHero: some View",
            range: standardHeroStart.upperBound..<heroSource.endIndex
        )
    )
    let batteryReadoutStart = try #require(
        heroSource.range(
            of: "private var batteryReadout: some View",
            range: accessibilityHeroStart.upperBound..<heroSource.endIndex
        )
    )
    let standardHero = String(heroSource[standardHeroStart.lowerBound..<accessibilityHeroStart.lowerBound])
    let accessibilityHero = String(heroSource[accessibilityHeroStart.lowerBound..<batteryReadoutStart.lowerBound])
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
    #expect(energyHero.contains("usesStackedLayout: usesStackedEnergyHeroLayout"))
    #expect(heroSource.contains("dynamicTypeSize.isAccessibilitySize || batteryNumericFontSize > 68"))
    #expect(heroSource.contains("@ScaledMetric(relativeTo: .largeTitle) private var batteryNumericFontSize"))
    #expect(heroSource.contains("@ScaledMetric(relativeTo: .title2) private var batteryPercentFontSize"))

    // The selected Home hero preserves a named copy-safe zone rather than
    // allowing the temporary scooter silhouette to cross battery text.
    #expect(homeSource.contains("static let batteryCopySafeWidth"))
    #expect(heroSource.contains("HomeHeroLayout.batteryCopySafeWidth"))
    #expect(homeSource.contains("static let scooterCenterXFraction"))
    #expect(homeSource.contains("static let batteryNumericSafeWidth: CGFloat = 120"))
    #expect(homeSource.contains("static let batteryCopySafeWidth: CGFloat = 108"))
    #expect(homeSource.contains("static let scooterWidthFraction: CGFloat = 0.80"))
    #expect(homeSource.contains("static let scooterMaximumSize: CGFloat = 278"))
    #expect(homeSource.contains("static let scooterCenterXFraction: CGFloat = 0.65"))

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

    let statusPanelStart = try #require(homeSource.range(of: "private var readinessAndToday: some View"))
    let controlsStart = try #require(homeSource.range(of: "private var controlsRail: some View", range: statusPanelStart.upperBound..<homeSource.endIndex))
    let statusPanel = String(homeSource[statusPanelStart.lowerBound..<controlsStart.lowerBound])

    #expect(statusPanel.contains("if dynamicTypeSize.isAccessibilitySize"))
    #expect(statusPanel.contains("spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 7"))
    #expect(statusPanel.contains("VStack(alignment: .leading, spacing: 12)"))
    #expect(statusPanel.contains("HStack(alignment: .top, spacing: 14)"))
    #expect(statusPanel.contains("Divider()"))
    #expect(statusPanel.contains(".fixedSize(horizontal: false, vertical: true)"))
    #expect(statusPanel.contains(".accessibilityIdentifier(\"home.horizon-entry\")"))
    #expect(statusPanel.contains("if let todayEvidenceDetail"))
    #expect(homeSource.contains(".padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 5)"))
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

    let headerStart = try #require(heroSource.range(of: "struct HomeVehicleHeaderBridge: View"))
    let panelStart = try #require(heroSource.range(of: "enum HomeBatteryFreshness: Equatable", range: headerStart.upperBound..<heroSource.endIndex))
    let header = String(heroSource[headerStart.lowerBound..<panelStart.lowerBound])
    #expect(header.contains("usesAccessibilityLayout: dynamicTypeSize.isAccessibilitySize"))
    #expect(header.contains("if usesAccessibilityLayout"))
    #expect(header.contains("VStack(alignment: .leading, spacing: 12)"))
    #expect(header.contains("Label(\"Vehicle controls\", systemImage: \"slider.horizontal.3\")"))
    #expect(header.contains(".labelStyle(.iconOnly)"))
    #expect(header.contains(".buttonStyle(.glassProminent)"))
    #expect(header.contains(".buttonBorderShape(.circle)"))
    #expect(header.contains(".font(.system(size: 19, weight: .bold))"))
    #expect(header.contains(".symbolRenderingMode(.monochrome)"))
    #expect(header.contains(".foregroundStyle(NembraColor.baseBlack)"))
    #expect(header.contains(".background(NembraColor.instrumentSecondaryText, in: Circle())"))
    #expect(header.contains(".tint(NembraColor.instrumentSecondaryText)"))
    #expect(!header.contains(".buttonStyle(.glass)"))
    #expect(!header.contains(".tint(NembraColor.warmGraphite)"))
    let vehicleControlsStart = try #require(
        header.range(of: "private var vehicleControlsLink: some View")
    )
    let indicatorStart = try #require(
        header.range(
            of: "private var indicatorColor: Color",
            range: vehicleControlsStart.upperBound..<header.endIndex
        )
    )
    let vehicleControls = String(
        header[vehicleControlsStart.lowerBound..<indicatorStart.lowerBound]
    )
    #expect(!vehicleControls.contains(".overlay"))
    #expect(!vehicleControls.contains("strokeBorder"))

    let batteryReadoutEnd = try #require(
        heroSource.range(
            of: "private var batteryBody: some View",
            range: batteryReadoutStart.upperBound..<heroSource.endIndex
        )
    )
    let batteryReadout = String(
        heroSource[batteryReadoutStart.lowerBound..<batteryReadoutEnd.lowerBound]
    )
    #expect(
        batteryReadout.components(separatedBy: ".foregroundStyle(batteryValueColor)").count == 3
    )
    #expect(!batteryReadout.contains("batteryValueColor.opacity"))
    #expect(heroSource.contains("return NembraColor.warningRed"))
    #expect(heroSource.contains("case (true, .percentage), (true, .estimatedRange):"))
    #expect(heroSource.contains("NembraColor.instrumentSecondaryText"))
    #expect(
        heroSource.contains(
            "Text(\"%\")\n                    .font(.system(size: batteryPercentFontSize, weight: .regular, design: .rounded))"
        )
    )
    #expect(!heroSource.contains("NembraColor.secondaryText.opacity(snapshot.isRetained"))

    #expect(
        readiness.contains(
            "Circle()\n                        .fill(NembraColor.instrumentSecondaryText)\n                        .frame(width: 4, height: 4)"
        )
    )
    #expect(!readiness.contains("Text(\"·\")"))

    let rangePrimaryColorStart = try #require(
        heroSource.range(of: "private var batteryRangePrimaryColor: Color")
    )
    let rangePrimaryColor = String(
        heroSource[rangePrimaryColorStart.lowerBound...]
    )
    #expect(rangePrimaryColor.contains("NembraColor.primaryText"))
    #expect(!rangePrimaryColor.contains(".opacity"))

    let recoveryStart = try #require(homeSource.range(of: "private var connectionRecovery: some View"))
    let recoveryEnd = try #require(homeSource.range(of: "private enum ConnectionRecoveryAction", range: recoveryStart.upperBound..<homeSource.endIndex))
    let recovery = String(homeSource[recoveryStart.lowerBound..<recoveryEnd.lowerBound])
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
    let homeSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraApp/Features/Home/HomeView.swift"),
        encoding: .utf8
    )
    let heroSource = try String(
        contentsOf: repositoryRoot.appendingPathComponent("NembraApp/Features/Home/VehicleHeroView.swift"),
        encoding: .utf8
    )

    let batteryBodyStart = try #require(heroSource.range(of: "private var batteryBody: some View"))
    let rangeCopyStart = try #require(
        heroSource.range(
            of: "private func batteryRangeCopy(",
            range: batteryBodyStart.upperBound..<heroSource.endIndex
        )
    )
    let readinessStart = try #require(
        heroSource.range(
            of: "private var batteryValueColor: Color",
            range: rangeCopyStart.upperBound..<heroSource.endIndex
        )
    )
    let batteryBody = String(heroSource[batteryBodyStart.lowerBound..<rangeCopyStart.lowerBound])
    let rangeCopy = String(heroSource[rangeCopyStart.lowerBound..<readinessStart.lowerBound])

    #expect(batteryBody.contains("HomeBatteryMaterial("))
    #expect(batteryBody.contains("fillFraction: CGFloat(snapshot.batteryFillFraction)"))
    #expect(batteryBody.contains("isLowBattery: snapshot.isLowBattery"))
    #expect(batteryBody.contains("if usesStackedLayout"))
    #expect(batteryBody.contains("accessibilityBatteryRangeCopy"))
    #expect(batteryBody.contains("batteryMaterial"))
    #expect(batteryBody.contains("batteryRangePrimaryColor"))
    #expect(batteryBody.contains("NembraColor.instrumentSecondaryText"))
    #expect(!batteryBody.contains(".mask"))
    #expect(rangeCopy.contains("HomeHeroLayout.batteryCopySafeWidth"))
    #expect(
        rangeCopy.contains(
            ".font(.system(.headline, design: .rounded, weight: batteryRangePrimaryWeight))"
        )
    )
    #expect(rangeCopy.contains(".font(.caption.weight(.regular))"))

    let materialStart = try #require(
        homeSource.range(of: "struct HomeBatteryMaterial: View, @MainActor Animatable")
    )
    let groundingStart = try #require(
        homeSource.range(
            of: "struct HomeHeroGroundingScene: View",
            range: materialStart.upperBound..<homeSource.endIndex
        )
    )
    let glassStart = try #require(
        homeSource.range(
            of: "private struct HomeControlIconGlassModifier: ViewModifier",
            range: groundingStart.upperBound..<homeSource.endIndex
        )
    )
    let material = String(homeSource[materialStart.lowerBound..<groundingStart.lowerBound])
    let grounding = String(homeSource[groundingStart.lowerBound..<glassStart.lowerBound])

    // The battery is a passive Canvas with a bounded SOC animation input. It
    // must never gain a TimelineView, display link, or glass material.
    #expect(material.contains("Canvas(opaque: false, rendersAsynchronously: false)"))
    #expect(material.contains("var animatableData: CGFloat"))
    #expect(material.contains("private static let chargeRibSpacing: CGFloat = 4"))
    #expect(material.contains("by: Self.chargeRibSpacing"))
    #expect(material.contains("chargeContext.clip(to: fillPath)"))
    #expect(material.contains("HomeHeroLayout.batteryCopySafeWidth + 34"))
    #expect(material.contains("copyWellRect.minX + fullCopyWellWidth"))
    #expect(material.contains("location: 0.90"))
    #expect(material.contains("copyWellPath"))
    #expect(material.contains("reservoirPath"))
    #expect(material.contains("terminalPath"))
    #expect(material.contains("shoulderPath"))
    #expect(material.contains("isLowBattery ? NembraColor.warningRed : NembraColor.gold"))
    #expect(material.contains("guard fillFraction > 0 else { return 0 }"))
    #expect(!material.contains("TimelineView"))
    #expect(!material.contains("glassEffect"))
    let ribsStart = try #require(material.range(of: "var ribs = Path()"))
    #expect(
        material.range(
            of: "let fullCopyWellWidth = HomeHeroLayout.batteryCopySafeWidth + 34",
            range: ribsStart.upperBound..<material.endIndex
        ) != nil
    )

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
        homeSource.range(of: "private var latestRideContinuation: some View")
    )
    let continuationLabelStart = try #require(
        homeSource.range(
            of: "private func latestRideLabel(",
            range: continuationStart.upperBound..<homeSource.endIndex
        )
    )
    let continuation = String(homeSource[continuationStart.lowerBound..<continuationLabelStart.lowerBound])
    #expect(continuation.contains(".nembraGlassControl()"))

    // Observation is resolved once at the narrow bridges. Require both actual
    // equality boundaries so a future extraction cannot silently turn the
    // snapshots back into ordinary recomputed children.
    let headerBridgeStart = try #require(
        heroSource.range(of: "struct HomeVehicleHeaderBridge: View")
    )
    let headerContentStart = try #require(
        heroSource.range(
            of: "private struct HomeVehicleHeaderContent: View, @MainActor Equatable",
            range: headerBridgeStart.upperBound..<heroSource.endIndex
        )
    )
    let headerBridge = String(
        heroSource[headerBridgeStart.lowerBound..<headerContentStart.lowerBound]
    )
    #expect(headerBridge.contains("HomeVehicleHeaderContent("))
    #expect(headerBridge.contains(".equatable()"))

    let energyBridgeStart = try #require(
        heroSource.range(of: "struct HomeEnergyHeroBridge: View")
    )
    let sceneStart = try #require(
        heroSource.range(
            of: "private struct HomeEnergyHeroScene: View, @MainActor Equatable",
            range: energyBridgeStart.upperBound..<heroSource.endIndex
        )
    )
    let energyBridge = String(
        heroSource[energyBridgeStart.lowerBound..<sceneStart.lowerBound]
    )
    #expect(energyBridge.contains("HomeEnergyHeroScene("))
    #expect(energyBridge.contains(".equatable()"))

    // The expensive renderer receives only an Equatable value and environment
    // primitives; it must not retain stores, callbacks, or state that could
    // freeze truth or widen the invalidation boundary.
    let scene = String(heroSource[sceneStart.lowerBound...])
    let sceneBodyStart = try #require(scene.range(of: "var body: some View"))
    let sceneDeclaration = String(scene[..<sceneBodyStart.lowerBound])
    #expect(scene.contains("let snapshot: HomeEnergyHeroSnapshot"))
    #expect(!scene.contains("VehicleStore"))
    #expect(!scene.contains("HorizonCockpitStore"))
    #expect(!scene.contains("@Environment"))
    #expect(!scene.contains("@Bindable"))
    #expect(!scene.contains("@State"))
    #expect(!scene.contains("TimelineView"))
    #expect(!sceneDeclaration.contains("->"))
    #expect(homeSource.contains("HomeVehicleHeaderBridge(vehicle: vehicle)"))
    #expect(homeSource.contains("HomeEnergyHeroBridge("))
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
    #expect(accessibilityXXXL.contains("performAccessibilityAudit(for: [.contrast, .textClipped])"))
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
