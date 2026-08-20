import Foundation
import NembraCore
import SwiftUI

/// The exact user-facing connection projection shared by the compact Home
/// header and Home's automatic-ride accessibility summary. It reads only the
/// authority-bearing store projections required to form visible connection
/// truth; raw cached speed never becomes live through this type.
struct HomeVehicleStatusPresentation: Equatable {
    enum Indicator: Equatable {
        case connected
        case transitional
        case offline
    }

    let text: String
    let accessibilityValue: String
    let indicator: Indicator

    @MainActor
    init(vehicle: VehicleStore) {
        let text = Self.statusText(vehicle: vehicle)
        self.text = text
        accessibilityValue = vehicle.profile == .simulatorQA
            ? "\(text). SIM, QA only, synthetic evidence"
            : text

        switch vehicle.state.connection {
        case .connected:
            indicator = .connected
        case .connecting, .reconnecting:
            indicator = .transitional
        case .disconnected:
            indicator = .offline
        }
    }

    @MainActor
    private static func statusText(vehicle: VehicleStore) -> String {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff: return "Bluetooth Off"
            case .bluetoothPermissionDenied: return "Permission Needed"
            case .scooterUnavailable: return "Not Found"
            case .unsupportedConfiguration: return "Unsupported Configuration"
            }
        }

        switch vehicle.state.connection {
        case .connected:
            guard vehicle.state.dataAvailability == .live else {
                return "Connected · waiting for data"
            }
            if let speed = vehicle.simulatorQualifiedLiveSpeedKilometersPerHour,
               speed > 0.5 {
                return "Riding · \(VehicleDisplayFormatting.speed(kilometersPerHour: speed))"
            }
            return "Connected"
        case .connecting:
            return "Connecting"
        case .reconnecting:
            return vehicle.state.dataAvailability == .retained
                ? "Reconnecting · last known data"
                : "Reconnecting"
        case .disconnected:
            return vehicle.state.dataAvailability == .retained
                ? "Offline · last known data"
                : "Offline"
        }
    }
}

/// Value-only inputs for the Home identity header. Unrelated battery, power,
/// odometer, command, and ride-store updates do not enter this render value.
struct HomeVehicleHeaderSnapshot: Equatable {
    let displayName: String
    let status: HomeVehicleStatusPresentation
    let showsSimulatorBadge: Bool

    @MainActor
    init(vehicle: VehicleStore) {
        showsSimulatorBadge = vehicle.profile == .simulatorQA
        displayName = showsSimulatorBadge
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
        status = HomeVehicleStatusPresentation(vehicle: vehicle)
    }
}

/// Observation stays at this narrow bridge. The actual header receives an
/// Equatable value so parent Home recomputation cannot redraw it for unrelated
/// vehicle fields.
@MainActor
struct HomeVehicleHeaderBridge: View {
    let vehicle: VehicleStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HomeVehicleHeaderContent(
            snapshot: HomeVehicleHeaderSnapshot(vehicle: vehicle),
            usesAccessibilityLayout: dynamicTypeSize.isAccessibilitySize
        )
        .equatable()
    }
}

private struct HomeVehicleHeaderContent: View, @MainActor Equatable {
    let snapshot: HomeVehicleHeaderSnapshot
    let usesAccessibilityLayout: Bool

    var body: some View {
        Group {
            if usesAccessibilityLayout {
                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    vehicleControlsLink
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    vehicleIdentity
                    Spacer(minLength: 8)
                    vehicleControlsLink
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.displayName)
                .font(
                    usesAccessibilityLayout
                        ? .title3.weight(.bold)
                        : .headline.weight(.semibold)
                )
                .tracking(0.2)
                .foregroundStyle(NembraColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(snapshot.status.text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NembraColor.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.showsSimulatorBadge {
                    Text("SIM · QA")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(NembraColor.gold)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 20)
                        .background(NembraColor.quietSurface, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(NembraColor.gold.opacity(0.22))
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vehicle connection")
            .accessibilityValue(snapshot.status.accessibilityValue)
            .accessibilityIdentifier("home.connection-status")
        }
    }

    private var vehicleControlsLink: some View {
        NavigationLink {
            VehicleControlsView()
        } label: {
            Label("Vehicle controls", systemImage: "slider.horizontal.3")
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.primaryText)
                .frame(
                    width: usesAccessibilityLayout ? 44 : 36,
                    height: usesAccessibilityLayout ? 44 : 36
                )
        }
        .buttonStyle(.glass)
        .tint(NembraColor.warmGraphite)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityHint("Opens detailed vehicle controls and verified settings.")
    }

    private var indicatorColor: Color {
        switch snapshot.status.indicator {
        case .connected: .green
        case .transitional: NembraColor.gold
        case .offline: NembraColor.secondaryText
        }
    }
}

enum HomeBatteryFreshness: Equatable {
    case unavailable
    case live
    case retained(observedAt: Date?)
}

/// Everything that can legitimately change the Home energy instrument. Speed,
/// power, odometer, trip, mode, locks, lights, and connection-copy fields are
/// intentionally absent so high-frequency telemetry cannot redraw its Canvases.
struct HomeEnergyHeroSnapshot: Equatable {
    let batteryPresentation: NembraCore.BatteryPrimaryReadoutPresentation
    let adaptiveRangeDecision: NembraCore.AdaptiveRangePrimaryPresentationDecision
    let freshness: HomeBatteryFreshness

    init(
        batteryPresentation: NembraCore.BatteryPrimaryReadoutPresentation,
        adaptiveRangeDecision: NembraCore.AdaptiveRangePrimaryPresentationDecision,
        freshness: HomeBatteryFreshness
    ) {
        self.batteryPresentation = batteryPresentation
        self.adaptiveRangeDecision = adaptiveRangeDecision
        self.freshness = freshness
    }

    @MainActor
    init(
        vehicle: VehicleStore,
        cockpit: HorizonCockpitStore,
        adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    ) {
        let decision = NembraCore.AdaptiveBatteryRangePrimaryPresentationPolicy()
            .resolve(liveEstimate: adaptiveRangeEstimate)
        let rangeDisplay: NembraCore.BatteryEstimatedRangeDisplay = switch decision {
        case let .valueMeters(meters): .valueMeters(meters)
        case .learning: .learning
        case .unavailable: .unavailable
        }

        batteryPresentation = cockpit.batteryPrimaryReadoutState.presentation(
            for: NembraCore.BatteryPrimaryReadoutInputs(
                displaySOCPercent: vehicle.batteryDisplayPercent,
                estimatedRange: rangeDisplay
            )
        )
        adaptiveRangeDecision = decision

        switch vehicle.batteryDataAvailability {
        case .unavailable:
            freshness = .unavailable
        case .live:
            freshness = .live
        case .retained:
            freshness = .retained(observedAt: vehicle.retainedBatteryObservedAt)
        }
    }

    var batteryReadoutMode: NembraCore.BatteryPrimaryReadoutMode {
        batteryPresentation.mode
    }

    var batteryPercent: Int? {
        batteryPresentation.batteryFillPercent
    }

    var batteryFillFraction: Double {
        Double(batteryPercent ?? 0) / 100
    }

    var isLowBattery: Bool {
        guard let batteryPercent else { return false }
        return batteryPercent <= 15
    }

    var isRetained: Bool {
        if case .retained = freshness { return true }
        return false
    }

    var retainedObservedAt: Date? {
        guard case let .retained(observedAt) = freshness else { return nil }
        return observedAt
    }

    var adaptiveRangeDisplay: NembraCore.BatteryEstimatedRangeDisplay {
        switch adaptiveRangeDecision {
        case let .valueMeters(meters): .valueMeters(meters)
        case .learning: .learning
        case .unavailable: .unavailable
        }
    }

    var adaptiveRangeText: String {
        switch adaptiveRangeDisplay {
        case let .valueMeters(meters):
            VehicleDisplayFormatting.distance(kilometers: meters / 1_000, decimals: 1)
        case .learning:
            "Learning"
        case .unavailable:
            "Unavailable"
        }
    }

    var adaptiveRangeQualifier: String {
        switch adaptiveRangeDecision {
        case .valueMeters:
            "learned range"
        case let .learning(reason), let .unavailable(reason):
            adaptiveRangeReasonQualifier(reason)
        }
    }

    var retainedBatteryFreshnessAccessibilityValue: String {
        guard let observedAt = retainedObservedAt else {
            return "Observation time unavailable"
        }
        return "Observed \(observedAt.formatted(date: .complete, time: .shortened))"
    }

    var batteryInstrumentAccessibilityLabel: String {
        switch batteryReadoutMode {
        case .percentage: "Battery and estimated range"
        case .estimatedRange: "Estimated range and battery"
        }
    }

    var batteryInstrumentAccessibilityValue: String {
        let emphasis = switch batteryReadoutMode {
        case .percentage: "Battery percentage emphasized"
        case .estimatedRange: "Estimated range emphasized"
        }
        return [batteryAccessibilityValue, adaptiveRangeAccessibilityValue, emphasis]
            .joined(separator: ". ")
    }

    var batteryInstrumentAccessibilityHint: String {
        let nextValue = batteryReadoutMode == .percentage
            ? "estimated range"
            : "battery percentage"
        return "Double tap to emphasize \(nextValue). Both values remain visible. The battery fill always represents state of charge."
    }

    private var batteryAccessibilityValue: String {
        guard let batteryPercent else { return "Unavailable" }
        var parts = ["\(batteryPercent) percent"]
        if isLowBattery { parts.append("low battery") }
        if isRetained {
            if let observedAt = retainedObservedAt {
                parts.append(
                    "last known, observed \(observedAt.formatted(date: .complete, time: .shortened))"
                )
            } else {
                parts.append("last known, observation time unavailable")
            }
        }
        return parts.joined(separator: ", ")
    }

    private var adaptiveRangeAccessibilityValue: String {
        switch adaptiveRangeDecision {
        case let .valueMeters(meters):
            let value = VehicleDisplayFormatting.distance(
                kilometers: meters / 1_000,
                decimals: 1
            )
            return "\(value), learned from accepted evidence for this scooter"
        case let .learning(reason):
            return "Learning from accepted ride history, \(adaptiveRangeReasonQualifier(reason))"
        case let .unavailable(reason):
            return "Unavailable, \(adaptiveRangeReasonQualifier(reason))"
        }
    }

    private func adaptiveRangeReasonQualifier(
        _ reason: NembraCore.AdaptiveRangePrimaryPresentationReason
    ) -> String {
        switch reason {
        case .provisionalSeed: "rides needed for range"
        case .learningConfidence: "building range history"
        case .lowConfidenceRequiresQualifier: "more rides for range"
        case .noEstimate: "no learned range"
        case .retainedEstimateRequiresQualifier: "fresh range evidence"
        }
    }
}

/// The only observing layer for Home's energy instrument. Its child render
/// island is value-only and Equatable; the persisted toggle remains owned by
/// the shared cockpit store and cannot mutate battery or range evidence.
@MainActor
struct HomeEnergyHeroBridge: View {
    @AppStorage(NembraPreferenceKey.haptics) private var hapticsEnabled = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .largeTitle) private var batteryNumericFontSize: CGFloat = 62
    @ScaledMetric(relativeTo: .title2) private var batteryPercentFontSize: CGFloat = 30

    let vehicle: VehicleStore
    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?

    private var usesStackedEnergyHeroLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || batteryNumericFontSize > 68
    }

    var body: some View {
        let snapshot = HomeEnergyHeroSnapshot(
            vehicle: vehicle,
            cockpit: cockpit,
            adaptiveRangeEstimate: adaptiveRangeEstimate
        )

        VStack(alignment: .leading, spacing: 10) {
            if snapshot.isRetained {
                Label {
                    if let observedAt = snapshot.retainedObservedAt {
                        HStack(spacing: 3) {
                            Text("Last confirmed")
                            Text(observedAt, style: .relative)
                        }
                    } else {
                        Text("Last confirmed · age unavailable")
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last confirmed battery")
                .accessibilityValue(snapshot.retainedBatteryFreshnessAccessibilityValue)
                .accessibilityHint("This battery value may be stale until the scooter reconnects.")
                .accessibilityIdentifier("home.battery.retained-freshness")
            }

            if snapshot.isLowBattery {
                Label("Low battery", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.warningRed)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Low battery")
                    .accessibilityIdentifier("home.battery.low-warning")
            }

            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    cockpit.toggleBatteryPrimaryReadout()
                }
            } label: {
                HomeEnergyHeroScene(
                    snapshot: snapshot,
                    usesStackedLayout: usesStackedEnergyHeroLayout,
                    reduceMotion: reduceMotion,
                    reduceTransparency: reduceTransparency,
                    batteryNumericFontSize: batteryNumericFontSize,
                    batteryPercentFontSize: batteryPercentFontSize
                )
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: snapshot.batteryReadoutMode) { _, _ in
                hapticsEnabled
            }
            .accessibilityLabel(snapshot.batteryInstrumentAccessibilityLabel)
            .accessibilityValue(snapshot.batteryInstrumentAccessibilityValue)
            .accessibilityHint(snapshot.batteryInstrumentAccessibilityHint)
            .accessibilityIdentifier("home.metric.battery")
        }
    }
}

/// Expensive passive visuals live below this value equality boundary. A speed
/// or power receipt can update the rest of Home without redrawing the battery
/// and grounding Canvases when these inputs are unchanged.
private struct HomeEnergyHeroScene: View, @MainActor Equatable {
    let snapshot: HomeEnergyHeroSnapshot
    let usesStackedLayout: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let batteryNumericFontSize: CGFloat
    let batteryPercentFontSize: CGFloat

    var body: some View {
        Group {
            if usesStackedLayout {
                accessibilityEnergyHero
            } else {
                standardEnergyHero
            }
        }
    }

    private var standardEnergyHero: some View {
        GeometryReader { proxy in
            let scooterSize = min(
                proxy.size.width * HomeHeroLayout.scooterWidthFraction,
                HomeHeroLayout.scooterMaximumSize
            )

            ZStack(alignment: .topLeading) {
                batteryReadout
                    .padding(.top, 2)

                batteryBody
                    .frame(height: HomeHeroLayout.batteryHeight)
                    .offset(y: HomeHeroLayout.batteryTop)

                HomeHeroGroundingScene(layout: .standard)
                    .equatable()
                    .frame(width: proxy.size.width, height: HomeHeroLayout.standardHeight)

                Image("ES80Side")
                    .resizable()
                    .scaledToFit()
                    .frame(width: scooterSize, height: scooterSize)
                    .shadow(color: .black.opacity(0.75), radius: 22, y: 16)
                    .shadow(color: NembraColor.gold.opacity(0.13), radius: 20, y: 18)
                    .position(
                        x: proxy.size.width * HomeHeroLayout.scooterCenterXFraction,
                        y: HomeHeroLayout.scooterCenterY
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: HomeHeroLayout.standardHeight)
        .clipped()
    }

    private var accessibilityEnergyHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            batteryReadout
            batteryBody
            ZStack(alignment: .bottom) {
                HomeHeroGroundingScene(layout: .accessibility)
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Image("ES80Side")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .shadow(color: .black.opacity(0.75), radius: 20, y: 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 230)
        }
    }

    private var batteryReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(snapshot.batteryPercent.map(String.init) ?? "—")
                .font(.system(size: batteryNumericFontSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(batteryValueColor)
                .contentTransition(reduceMotion ? .identity : .numericText())

            if snapshot.batteryPercent != nil {
                Text("%")
                    .font(.system(size: batteryPercentFontSize, weight: .light, design: .rounded))
                    .foregroundStyle(batteryValueColor)
            }
        }
        .frame(
            maxWidth: usesStackedLayout
                ? .infinity
                : HomeHeroLayout.batteryNumericSafeWidth,
            alignment: .leading
        )
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityHidden(true)
    }

    private var batteryBody: some View {
        Group {
            if usesStackedLayout {
                VStack(alignment: .leading, spacing: 12) {
                    batteryMaterial
                        .frame(height: 94)
                    accessibilityBatteryRangeCopy
                }
            } else {
                ZStack(alignment: .leading) {
                    batteryMaterial
                    batteryRangeCopy(
                        primaryColor: batteryRangePrimaryColor,
                        secondaryColor: NembraColor.instrumentSecondaryText
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var batteryMaterial: some View {
        HomeBatteryMaterial(
            fillFraction: CGFloat(snapshot.batteryFillFraction),
            isLowBattery: snapshot.isLowBattery,
            reduceTransparency: reduceTransparency
        )
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.28),
            value: snapshot.batteryFillFraction
        )
    }

    private var accessibilityBatteryRangeCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.adaptiveRangeText)
                .font(.system(.headline, design: .rounded, weight: batteryRangePrimaryWeight))
                .tracking(0.15)
                .monospacedDigit()
                .foregroundStyle(batteryRangePrimaryColor)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .fixedSize(horizontal: false, vertical: true)

            Text(snapshot.adaptiveRangeQualifier)
                .font(.caption.weight(.regular))
                .tracking(0.28)
                .foregroundStyle(NembraColor.instrumentSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func batteryRangeCopy(
        primaryColor: Color,
        secondaryColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.adaptiveRangeText)
                .font(.system(.headline, design: .rounded, weight: batteryRangePrimaryWeight))
                .tracking(0.15)
                .monospacedDigit()
                .foregroundStyle(primaryColor)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(snapshot.adaptiveRangeQualifier)
                .font(.caption.weight(.regular))
                .tracking(0.28)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(
            maxWidth: HomeHeroLayout.batteryCopySafeWidth,
            alignment: .leading
        )
        .padding(.leading, 16)
        .padding(.trailing, HomeHeroLayout.batteryTerminalWidth + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var batteryValueColor: Color {
        if snapshot.isLowBattery {
            return NembraColor.warningRed
        }

        switch (snapshot.isRetained, snapshot.batteryReadoutMode) {
        case (false, .percentage):
            return NembraColor.primaryText
        case (false, .estimatedRange):
            return NembraColor.instrumentSecondaryText
        case (true, .percentage), (true, .estimatedRange):
            return NembraColor.primaryText
        }
    }

    private var batteryRangePrimaryWeight: Font.Weight {
        switch snapshot.adaptiveRangeDisplay {
        case .valueMeters:
            snapshot.batteryReadoutMode == .estimatedRange ? .semibold : .medium
        case .learning:
            .medium
        case .unavailable:
            .regular
        }
    }

    private var batteryRangePrimaryColor: Color {
        switch snapshot.adaptiveRangeDisplay {
        case .valueMeters:
            NembraColor.primaryText.opacity(snapshot.isRetained ? 0.90 : 0.96)
        case .learning:
            NembraColor.primaryText.opacity(snapshot.isRetained ? 0.88 : 0.92)
        case .unavailable:
            NembraColor.primaryText.opacity(snapshot.isRetained ? 0.86 : 0.90)
        }
    }
}
