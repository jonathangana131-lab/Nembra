import Foundation
import NembraCore
import SwiftUI

/// Source-compatible visual-only policy retained for the existing presentation
/// regression test. Horizon V4 does not consume this legacy personality or let
/// ride mode alter telemetry, propulsion geometry, commands, or evidence.
struct DashboardModePersonality: Equatable {
    let mode: RideMode?
    let ambientOpacity: Double
    let speedScale: CGFloat

    static func resolved(for mode: RideMode?) -> DashboardModePersonality {
        switch mode {
        case .walk: DashboardModePersonality(mode: .walk, ambientOpacity: 0.018, speedScale: 0.96)
        case .eco: DashboardModePersonality(mode: .eco, ambientOpacity: 0.030, speedScale: 0.98)
        case .drive: DashboardModePersonality(mode: .drive, ambientOpacity: 0.044, speedScale: 1.0)
        case .sport: DashboardModePersonality(mode: .sport, ambientOpacity: 0.062, speedScale: 1.025)
        case nil: DashboardModePersonality(mode: nil, ambientOpacity: 0.012, speedScale: 1.0)
        }
    }
}

/// Selected Horizon V4 Drive composition.
///
/// This screen reads accepted app/domain projections. It never increments ride
/// totals, creates range estimates, promotes interpolated frames, or turns
/// Simulator QA fixtures into physical AOVOPRO evidence.
@MainActor
struct DashboardView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    let onHome: () -> Void
    let onNavigate: () -> Void

    init(
        cockpit: HorizonCockpitStore,
        adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate? = nil,
        onHome: @escaping () -> Void,
        onNavigate: @escaping () -> Void
    ) {
        self.cockpit = cockpit
        self.adaptiveRangeEstimate = adaptiveRangeEstimate
        self.onHome = onHome
        self.onNavigate = onNavigate
    }

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let horizontalPadding = max(16, min(24, proxy.size.width * 0.024))
            let topPadding = max(10, insets.top + 8)
            let bottomPadding = max(8, insets.bottom + 7)
            let slowLayout = DashboardDriveSlowLayout(
                viewportWidth: proxy.size.width,
                viewportHeight: proxy.size.height,
                safeAreaTop: insets.top,
                safeAreaLeading: insets.leading,
                safeAreaBottom: insets.bottom,
                safeAreaTrailing: insets.trailing,
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                bottomPadding: bottomPadding
            )

            ZStack {
                cockpitBackground
                    .ignoresSafeArea()

                DashboardSpeedInstrumentView()
                    .padding(.leading, insets.leading + horizontalPadding)
                    .padding(.trailing, insets.trailing + horizontalPadding)
                    .padding(.top, topPadding)
                    .padding(.bottom, bottomPadding)

                DashboardDriveSnapshotBridge(
                    cockpit: cockpit,
                    adaptiveRangeEstimate: adaptiveRangeEstimate,
                    layout: slowLayout
                )

                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        DashboardFunctionalActionControls(
                            onHome: onHome,
                            onNavigate: onNavigate
                        )
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, insets.leading + horizontalPadding)
                .padding(.trailing, insets.trailing + horizontalPadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
        }
        .foregroundStyle(NembraColor.primaryText)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.cockpit")
    }

    private var cockpitBackground: some View {
        ZStack {
            NembraColor.baseBlack

            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        NembraColor.gold.opacity(colorSchemeContrast == .increased ? 0.07 : 0.12),
                        NembraColor.deepGold.opacity(0.035),
                        .clear
                    ],
                    center: UnitPoint(x: 0.50, y: 0.56),
                    startRadius: 10,
                    endRadius: 310
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct DashboardDriveSlowLayout: Equatable {
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat
    let safeAreaTop: CGFloat
    let safeAreaLeading: CGFloat
    let safeAreaBottom: CGFloat
    let safeAreaTrailing: CGFloat
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat
}

/// Stable, low-frequency projection for Dashboard chrome and the durable ride
/// ledger. High-frequency speed, power, and `VehicleState.lastUpdated` are
/// intentionally absent; those values stay inside `DashboardSpeedInstrumentView`.
private struct DashboardDriveSnapshot: Equatable {
    enum Connection: Equatable {
        case connected
        case connecting
        case reconnecting
        case disconnected
    }

    enum ConnectionIssue: Equatable {
        case bluetoothPoweredOff
        case bluetoothPermissionDenied
        case scooterUnavailable
        case unsupportedConfiguration
    }

    let isSimulatorQA: Bool
    let connection: Connection
    let connectionIssue: ConnectionIssue?
    let batteryPresentation: NembraCore.BatteryPrimaryReadoutPresentation
    let batteryDataAvailability: VehicleDataAvailability
    let adaptiveRangeDisplay: NembraCore.BatteryEstimatedRangeDisplay
    let odometerKilometers: Double?
    let odometerIsRetained: Bool
    let rideStatus: RideApplicationStatus
    let dailyStatus: DailyRidePresentationStatus
    let todayDistanceSummary: NembraCore.DailyRideMetricSummary?
    let currentRideDurationSummary: NembraCore.DailyRideMetricSummary?
    let hasCurrentRide: Bool
    let isAutomaticCaptureEnabled: Bool
    let canCaptureRideTelemetryWithoutOpeningApp: Bool

    @MainActor
    init(
        vehicle: VehicleStore,
        rides: RideApplicationStore,
        daily: DailyRidePresentationStore,
        automaticCapture: AutomaticCaptureReadinessStore,
        cockpit: HorizonCockpitStore,
        adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    ) {
        let vehicleState = vehicle.state
        let isSimulatorQA = vehicle.profile == .simulatorQA
        let adaptiveRangeDisplay = NembraCore.AdaptiveBatteryRangePrimaryPresentationPolicy()
            .resolve(liveEstimate: adaptiveRangeEstimate)
        let odometerKilometers: Double? = if isSimulatorQA,
                                            vehicle.profile.capabilities.supportsOdometer,
                                            let value = vehicleState.odometerKilometers,
                                            value.isFinite,
                                            value >= 0 {
            value
        } else {
            nil
        }

        self.isSimulatorQA = isSimulatorQA
        self.connection = switch vehicleState.connection {
        case .connected: .connected
        case .connecting: .connecting
        case .reconnecting: .reconnecting
        case .disconnected: .disconnected
        }
        self.connectionIssue = switch vehicleState.connectionIssue {
        case .bluetoothPoweredOff: .bluetoothPoweredOff
        case .bluetoothPermissionDenied: .bluetoothPermissionDenied
        case .scooterUnavailable: .scooterUnavailable
        case .unsupportedConfiguration: .unsupportedConfiguration
        case nil: nil
        }
        self.batteryPresentation = cockpit.batteryPrimaryReadoutState.presentation(
            for: NembraCore.BatteryPrimaryReadoutInputs(
                displaySOCPercent: vehicle.batteryDisplayPercent,
                estimatedRange: adaptiveRangeDisplay
            )
        )
        self.batteryDataAvailability = vehicle.batteryDataAvailability
        self.adaptiveRangeDisplay = adaptiveRangeDisplay
        self.odometerKilometers = odometerKilometers
        self.odometerIsRetained = odometerKilometers != nil && vehicleState.connection != .connected
        self.rideStatus = rides.status
        self.dailyStatus = daily.status
        self.todayDistanceSummary = daily.todayAndCurrent?.today.distanceMeters
        self.currentRideDurationSummary = daily.todayAndCurrent?.currentRide?.durationSeconds
        self.hasCurrentRide = daily.todayAndCurrent?.currentRide != nil
        self.isAutomaticCaptureEnabled = automaticCapture.isAutomaticCaptureEnabled
        self.canCaptureRideTelemetryWithoutOpeningApp = automaticCapture.readiness
            .canCaptureRideTelemetryWithoutOpeningApp
    }
}

/// The sole environment bridge for slow Dashboard data. Observation may revisit
/// this tiny projection when monolithic `VehicleStore.state` changes, but the
/// equatable layer below is not re-rendered unless a visible slow fact changes.
@MainActor
private struct DashboardDriveSnapshotBridge: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(RideApplicationStore.self) private var rides
    @Environment(DailyRidePresentationStore.self) private var daily
    @Environment(AutomaticCaptureReadinessStore.self) private var automaticCapture

    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    let layout: DashboardDriveSlowLayout

    var body: some View {
        DashboardDriveSlowLayer(
            snapshot: DashboardDriveSnapshot(
                vehicle: vehicle,
                rides: rides,
                daily: daily,
                automaticCapture: automaticCapture,
                cockpit: cockpit,
                adaptiveRangeEstimate: adaptiveRangeEstimate
            ),
            cockpit: cockpit,
            layout: layout
        )
        .equatable()
    }
}

@MainActor
private struct DashboardFunctionalActionControls: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let onHome: () -> Void
    let onNavigate: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                cockpitAction(
                    title: "Home",
                    systemImage: "house",
                    emphasized: false,
                    action: onHome
                )
                cockpitAction(
                    title: "Navigate",
                    systemImage: "location.north.line.fill",
                    emphasized: true,
                    action: onNavigate
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cockpit controls")
    }

    private func cockpitAction(
        title: String,
        systemImage: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(emphasized ? NembraColor.gold : NembraColor.primaryText.opacity(0.82))
                .lineLimit(1)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 10 : 14)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }

        return Group {
            if reduceTransparency {
                button
                    .buttonStyle(.plain)
                    .background {
                        Capsule(style: .continuous)
                            .fill(NembraColor.warmGraphite)
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(
                                        emphasized ? NembraColor.gold.opacity(0.44) : Color.white.opacity(0.22),
                                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                                    )
                            }
                    }
            } else {
                button
                    .buttonStyle(.glass)
            }
        }
        .accessibilityIdentifier("dashboard.control.\(title.lowercased())")
    }
}

@MainActor
private struct DashboardDriveSlowLayer: View, Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: DashboardDriveSnapshot
    let cockpit: HorizonCockpitStore
    let layout: DashboardDriveSlowLayout

    static func == (lhs: DashboardDriveSlowLayer, rhs: DashboardDriveSlowLayer) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.cockpit === rhs.cockpit
            && lhs.layout == rhs.layout
    }

    var body: some View {
        ZStack {
            adaptiveRangeReadout
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 92 : 118)
                .position(
                    x: layout.viewportWidth - layout.safeAreaTrailing - layout.horizontalPadding - 59,
                    y: max(112, layout.viewportHeight * 0.31)
                )

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                rideLedger
            }
            .padding(.leading, layout.safeAreaLeading + layout.horizontalPadding)
            .padding(.trailing, layout.safeAreaTrailing + layout.horizontalPadding)
            .padding(.top, layout.topPadding)
            .padding(.bottom, layout.bottomPadding)
        }
        .frame(width: layout.viewportWidth, height: layout.viewportHeight)
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                batteryControl
                    .layoutPriority(2)

                Spacer(minLength: 170)
            }

            vehicleIdentity
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 150 : 210)
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 58 : 54)
        .accessibilityIdentifier("dashboard.top-chrome")
    }

    private var vehicleIdentity: some View {
        VStack(spacing: 4) {
            HStack(spacing: 7) {
                Text("AOVOPRO ES80")
                    .font(.caption.weight(.bold))
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0.8 : 2.6)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if isSimulatorQA {
                    Text("QA ONLY")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(NembraColor.gold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(NembraColor.gold.opacity(0.10), in: Capsule())
                        .accessibilityLabel("Simulator QA disclosure")
                        .accessibilityValue("Synthetic evidence, not physical scooter truth")
                        .accessibilityIdentifier("dashboard.qa-disclosure")
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(connectionStatusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(NembraColor.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: isSimulatorQA ? .contain : .ignore)
        .accessibilityLabel("AOVOPRO ES80")
        .accessibilityValue(identityAccessibilityValue)
        .accessibilityIdentifier("dashboard.vehicle-identity")
    }

    private var batteryControl: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                cockpit.toggleBatteryPrimaryReadout()
            }
        } label: {
            HStack(spacing: 10) {
                DashboardBatteryInstrument(
                    fillFraction: batteryFillFraction,
                    label: batteryPrimaryText,
                    isRetained: snapshot.batteryDataAvailability == .retained,
                    isLow: isBatteryLow
                )
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 132 : 154, height: 40)

                if !dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NembraColor.primaryText.opacity(0.92))
                        Text(batterySecondaryText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(NembraColor.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: snapshot.batteryPresentation.mode)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batteryAccessibilityLabel)
        .accessibilityValue(qualifiedForSimulator(batteryAccessibilityValue))
        .accessibilityHint("Double tap to switch between battery percentage and adaptive range. The fill always represents battery charge.")
        .accessibilityIdentifier("dashboard.battery-range")
    }

    private var rideLedger: some View {
        ViewThatFits(in: .horizontal) {
            standardRideLedger
            compactRideLedger
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 62)
        .accessibilityIdentifier("dashboard.ride-ledger")
    }

    private var adaptiveRangeReadout: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("ADAPTIVE RANGE")
                .font(.system(size: 8, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(NembraColor.secondaryText.opacity(0.72))
                .lineLimit(1)

            Text(adaptiveRangeText)
                .font(.title2.weight(.light).monospacedDigit())
                .foregroundStyle(adaptiveRangeNumericMeters == nil ? NembraColor.secondaryText : NembraColor.primaryText.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(adaptiveRangeQualifier)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(NembraColor.secondaryText.opacity(0.62))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adaptive range")
        .accessibilityValue(qualifiedForSimulator(adaptiveRangeAccessibilityValue))
        .accessibilityIdentifier("dashboard.adaptive-range")
    }

    private var standardRideLedger: some View {
        HStack(alignment: .bottom, spacing: 18) {
            recordingStatus
                .frame(minWidth: 205, alignment: .leading)

            Spacer(minLength: 8)

            ledgerMetric(
                title: "TODAY",
                value: todayDistanceText,
                qualifier: dailyMetricQualifier(todayDistanceSummary),
                identifier: "dashboard.today"
            )
            ledgerMetric(
                title: "RIDE TIME",
                value: currentRideDurationText,
                qualifier: dailyMetricQualifier(currentRideDurationSummary),
                identifier: "dashboard.ride-time"
            )
            ledgerMetric(
                title: "ODOMETER",
                value: odometerText,
                qualifier: retainedVehicleQualifier,
                identifier: "dashboard.odometer"
            )

            Spacer(minLength: 8)

            ledgerMetric(
                title: "CITY EXPLORED",
                value: "—",
                qualifier: "NOT VERIFIED",
                identifier: "dashboard.city-explored",
                alignment: .trailing
            )
        }
    }

    private var compactRideLedger: some View {
        HStack(alignment: .bottom, spacing: 12) {
            recordingStatus
                .frame(maxWidth: .infinity, alignment: .leading)
            ledgerMetric(
                title: "TODAY",
                value: todayDistanceText,
                qualifier: dailyMetricQualifier(todayDistanceSummary),
                identifier: "dashboard.today"
            )
            ledgerMetric(
                title: "RIDE",
                value: currentRideDurationText,
                qualifier: dailyMetricQualifier(currentRideDurationSummary),
                identifier: "dashboard.ride-time"
            )
            ledgerMetric(
                title: "ODOMETER",
                value: odometerText,
                qualifier: retainedVehicleQualifier,
                identifier: "dashboard.odometer"
            )
            ledgerMetric(
                title: "CITY",
                value: "—",
                qualifier: "NOT VERIFIED",
                identifier: "dashboard.city-explored"
            )
        }
    }

    private var recordingStatus: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .strokeBorder(recordingStatusColor, lineWidth: 2)
                .frame(width: 12, height: 12)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(recordingStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText.opacity(0.80))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(recordingStatusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Automatic ride recording")
        .accessibilityValue(qualifiedForSimulator("\(recordingStatusTitle). \(recordingStatusSubtitle)"))
        .accessibilityIdentifier("dashboard.recording-status")
    }

    private func ledgerMetric(
        title: String,
        value: String,
        qualifier: String?,
        identifier: String,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(NembraColor.secondaryText.opacity(0.70))
                .lineLimit(1)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(value == "—" ? NembraColor.secondaryText : NembraColor.primaryText.opacity(0.78))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let qualifier {
                Text(qualifier)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(qualifiedForSimulator(metricAccessibilityValue(value: value, qualifier: qualifier)))
        .accessibilityIdentifier(identifier)
    }

    private var batteryPresentation: NembraCore.BatteryPrimaryReadoutPresentation {
        snapshot.batteryPresentation
    }

    private var batteryEstimatedRangeDisplay: NembraCore.BatteryEstimatedRangeDisplay {
        snapshot.adaptiveRangeDisplay
    }

    private var batteryPrimaryText: String {
        switch batteryPresentation.primaryValue {
        case let .percentage(percent): "\(percent)%"
        case let .estimatedRangeMeters(meters): rangeText(meters: meters)
        case .learningRange: "Learning"
        case .unavailable: "—"
        }
    }

    private var batterySecondaryText: String {
        switch batteryPresentation.mode {
        case .percentage:
            adaptiveRangeNumericMeters == nil ? "tap for adaptive range" : "tap for learned range"
        case .estimatedRange:
            snapshot.batteryDataAvailability == .retained ? "last known charge fill" : "fill remains battery charge"
        }
    }

    private var batteryAccessibilityLabel: String {
        switch batteryPresentation.mode {
        case .percentage: "Battery"
        case .estimatedRange: "Adaptive range"
        }
    }

    private var batteryAccessibilityValue: String {
        let qualifier = snapshot.batteryDataAvailability == .retained ? "Last known. " : ""
        switch batteryPresentation.primaryValue {
        case let .percentage(percent):
            return "\(qualifier)\(percent) percent. Fill represents state of charge."
        case let .estimatedRangeMeters(meters):
            return "\(rangeText(meters: meters)), learned from accepted scooter evidence. Fill represents state of charge."
        case .learningRange:
            return "Learning from accepted scooter evidence. Fill represents state of charge."
        case .unavailable:
            return "Unavailable until display-authoritative battery and learned-range evidence exist."
        }
    }

    private var batteryFillFraction: CGFloat? {
        guard let percent = batteryPresentation.batteryFillPercent else { return nil }
        return CGFloat(percent) / 100
    }

    private var isBatteryLow: Bool {
        guard let percent = batteryPresentation.batteryFillPercent else { return false }
        return percent <= 15 && snapshot.batteryDataAvailability == .live
    }

    private var adaptiveRangeNumericMeters: Double? {
        if case let .valueMeters(meters) = batteryEstimatedRangeDisplay { return meters }
        return nil
    }

    private var adaptiveRangeText: String {
        switch batteryEstimatedRangeDisplay {
        case let .valueMeters(meters): rangeText(meters: meters)
        case .learning: "Learning"
        case .unavailable: "—"
        }
    }

    private var adaptiveRangeQualifier: String {
        switch batteryEstimatedRangeDisplay {
        case .valueMeters: "learned from this scooter"
        case .learning: "building accepted ride history"
        case .unavailable: "needs verified scooter history"
        }
    }

    private var adaptiveRangeAccessibilityValue: String {
        switch batteryEstimatedRangeDisplay {
        case let .valueMeters(meters):
            return "\(rangeText(meters: meters)), learned from accepted evidence for this scooter"
        case .learning:
            return "Learning from accepted ride history"
        case .unavailable:
            return "Unavailable until a verified learned range model exists"
        }
    }

    private func rangeText(meters: Double) -> String {
        VehicleDisplayFormatting.distance(kilometers: meters / 1_000, decimals: 1)
    }

    private var todayDistanceSummary: NembraCore.DailyRideMetricSummary? {
        snapshot.todayDistanceSummary
    }

    private var currentRideDurationSummary: NembraCore.DailyRideMetricSummary? {
        snapshot.currentRideDurationSummary
    }

    private var todayDistanceText: String {
        guard let meters = todayDistanceSummary?.value else { return "—" }
        return VehicleDisplayFormatting.distance(kilometers: meters / 1_000)
    }

    private var currentRideDurationText: String {
        guard let seconds = currentRideDurationSummary?.value,
              seconds.isFinite,
              seconds >= 0 else { return "—" }
        let roundedSeconds = Int(seconds.rounded(.down))
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private var odometerText: String {
        // The public app has no field-specific odometer authority yet. Simulator
        // QA owns an explicit synthetic source; every physical profile remains
        // unavailable until Capture promotes a verified odometer projection.
        VehicleDisplayFormatting.distance(kilometers: snapshot.odometerKilometers)
    }

    private var retainedVehicleQualifier: String? {
        guard odometerText != "—" else { return "UNAVAILABLE" }
        return snapshot.odometerIsRetained ? "LAST KNOWN" : nil
    }

    private func dailyMetricQualifier(_ summary: NembraCore.DailyRideMetricSummary?) -> String? {
        switch snapshot.dailyStatus {
        case .failed:
            return "STORAGE FAILED"
        case .unavailable:
            return "UNAVAILABLE"
        case .loading where summary != nil:
            return "LAST SAVED"
        case .idle, .loading, .ready:
            break
        }

        guard let summary else {
            switch snapshot.dailyStatus {
            case .loading: return "LOADING"
            case .failed: return "STORAGE FAILED"
            case .unavailable: return "UNAVAILABLE"
            case .idle, .ready: return "NO EVIDENCE"
            }
        }
        return switch summary.availability {
        case .complete: nil
        case .partial: "PARTIAL EVIDENCE"
        case .unavailable: "UNAVAILABLE"
        case .noEvidence: "NO EVIDENCE"
        }
    }

    private var recordingStatusTitle: String {
        switch snapshot.rideStatus {
        case .persistenceUnavailable, .failed:
            return "Recording unavailable"
        case .restoring:
            return "Restoring ride"
        case .candidate:
            return "Detecting ride"
        case .active:
            return "Recording automatically"
        case .temporarilyDisconnected:
            return "Ride protected"
        case .endingCandidate:
            return "Checking ride end"
        case .saving:
            return "Saving ride"
        case .disabled:
            return "Automatic recording unavailable"
        case .idle:
            guard snapshot.isAutomaticCaptureEnabled else {
                return "Automatic recording off"
            }
            return snapshot.canCaptureRideTelemetryWithoutOpeningApp
                ? "Automatic recording ready"
                : "Automatic recording blocked"
        }
    }

    private var recordingStatusSubtitle: String {
        let truth: String = switch snapshot.rideStatus {
        case .persistenceUnavailable, .failed:
            "Accepted progress cannot be saved safely"
        case .restoring:
            "Recovering the last durable checkpoint"
        case .candidate:
            "Waiting for accepted movement evidence"
        case .active:
            "Today continues across every stop"
        case .temporarilyDisconnected:
            "Waiting through the reconnect grace period"
        case .endingCandidate:
            "Waiting for accepted ride-end evidence"
        case .saving:
            "Committing accepted ride evidence"
        case .disabled:
            "Verified production tracking is not configured"
        case .idle:
            if !snapshot.isAutomaticCaptureEnabled {
                "Enable after one-time setup when wanted"
            } else if snapshot.canCaptureRideTelemetryWithoutOpeningApp {
                "Best effort within iOS background limits"
            } else {
                "Open Settings to finish required setup"
            }
        }
        return isSimulatorQA ? "Simulator QA synthetic evidence · \(truth)" : truth
    }

    private var recordingStatusColor: Color {
        switch snapshot.rideStatus {
        case .persistenceUnavailable, .failed:
            return .red
        case .candidate, .active, .temporarilyDisconnected, .endingCandidate, .saving, .restoring:
            return NembraColor.gold
        case .disabled:
            return NembraColor.secondaryText.opacity(0.55)
        case .idle:
            return snapshot.canCaptureRideTelemetryWithoutOpeningApp
                ? NembraColor.gold.opacity(0.82)
                : NembraColor.secondaryText.opacity(0.55)
        }
    }

    private var connectionStatusText: String {
        let base: String
        if let issue = snapshot.connectionIssue {
            base = switch issue {
            case .bluetoothPoweredOff: "Bluetooth off"
            case .bluetoothPermissionDenied: "Bluetooth permission needed"
            case .scooterUnavailable: "Scooter unavailable"
            case .unsupportedConfiguration: "Unsupported configuration"
            }
        } else {
            base = switch snapshot.connection {
            case .connected: "Connected"
            case .connecting: "Connecting"
            case .reconnecting: "Reconnecting"
            case .disconnected: "Offline"
            }
        }

        if isSimulatorQA { return "\(base) · Simulator QA" }
        if snapshot.hasCurrentRide { return "\(base) · ride recording" }
        return base
    }

    private var connectionColor: Color {
        switch snapshot.connection {
        case .connected: .green
        case .connecting, .reconnecting: NembraColor.gold
        case .disconnected: NembraColor.secondaryText.opacity(0.55)
        }
    }

    private var identityAccessibilityValue: String {
        qualifiedForSimulator(connectionStatusText)
    }

    private var isSimulatorQA: Bool {
        snapshot.isSimulatorQA
    }

    private func qualifiedForSimulator(_ value: String) -> String {
        isSimulatorQA ? "Simulator QA synthetic evidence, not physical scooter truth. \(value)" : value
    }

    private func metricAccessibilityValue(value: String, qualifier: String?) -> String {
        if let qualifier { return "\(value), \(qualifier.lowercased())" }
        return value
    }
}

private struct DashboardBatteryInstrument: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let fillFraction: CGFloat?
    let label: String
    let isRetained: Bool
    let isLow: Bool

    var body: some View {
        GeometryReader { proxy in
            let terminalWidth = max(5, proxy.size.width * 0.035)
            let shellWidth = proxy.size.width - terminalWidth - 3
            let shellRect = CGRect(x: 0, y: 0, width: shellWidth, height: proxy.size.height)
            let innerInset: CGFloat = 4
            let innerWidth = max(0, shellRect.width - innerInset * 2)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: proxy.size.height * 0.42, style: .continuous)
                    .fill(NembraColor.quietSurface)
                    .overlay {
                        RoundedRectangle(cornerRadius: proxy.size.height * 0.42, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorSchemeContrast == .increased ? 0.55 : 0.34),
                                lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                            )
                    }
                    .frame(width: shellRect.width, height: shellRect.height)

                if let fillFraction, fillFraction > 0 {
                    RoundedRectangle(cornerRadius: max(5, (proxy.size.height - innerInset * 2) * 0.40), style: .continuous)
                        .fill(fillColor)
                        .frame(
                            width: max(3, innerWidth * min(max(fillFraction, 0), 1)),
                            height: proxy.size.height - innerInset * 2
                        )
                        .padding(innerInset)
                        .opacity(isRetained ? 0.48 : 1)
                }

                Text(label)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(labelForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .frame(width: shellRect.width, height: shellRect.height)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0.58 : 0.42))
                    .frame(width: terminalWidth, height: proxy.size.height * 0.36)
                    .offset(x: shellRect.width + 3)
            }
        }
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        if isLow { return .red }
        return Color.white.opacity(reduceTransparency ? 0.90 : 0.84)
    }

    private var labelForeground: Color {
        guard label != "—" else { return NembraColor.secondaryText }
        guard let fillFraction, fillFraction >= 0.52 else { return NembraColor.primaryText }
        return Color.black.opacity(isLow ? 0.86 : 0.92)
    }
}
