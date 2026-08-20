import Foundation
import NembraCore
import SwiftUI

/// Native post-V4 Drive composition for the mounted-phone cockpit.
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

            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.039, blue: 0.043),
                    NembraColor.baseBlack,
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if !reduceTransparency {
                EllipticalGradient(
                    colors: [
                        NembraColor.gold.opacity(colorSchemeContrast == .increased ? 0.055 : 0.105),
                        NembraColor.deepGold.opacity(0.028),
                        .clear
                    ],
                    center: UnitPoint(x: 0.50, y: 0.72),
                    startRadiusFraction: 0.02,
                    endRadiusFraction: 0.58
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            LinearGradient(
                colors: [
                    .clear,
                    Color.white.opacity(colorSchemeContrast == .increased ? 0.035 : 0.018),
                    Color.black.opacity(0.28)
                ],
                startPoint: UnitPoint(x: 0.5, y: 0.54),
                endPoint: .bottom
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    let adaptiveRangeConfidence: NembraCore.AdaptiveRangeConfidence?
    let odometerKilometers: Double?
    let odometerIsRetained: Bool
    let rideStatus: RideApplicationStatus
    let dailyStatus: DailyRidePresentationStatus
    let todayDistanceSummary: NembraCore.DailyRideMetricSummary?
    let currentRideDurationSummary: NembraCore.DailyRideMetricSummary?
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
        let adaptiveRangeDecision = NembraCore.AdaptiveBatteryRangePrimaryPresentationPolicy()
            .resolve(liveEstimate: adaptiveRangeEstimate)
        let adaptiveRangeDisplay: NembraCore.BatteryEstimatedRangeDisplay = switch adaptiveRangeDecision {
        case let .valueMeters(meters): .valueMeters(meters)
        case .learning: .learning
        case .unavailable: .unavailable
        }
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
        self.adaptiveRangeConfidence = switch adaptiveRangeDecision {
        case .valueMeters:
            switch adaptiveRangeEstimate?.estimate.confidence {
            case .normal, .high: adaptiveRangeEstimate?.estimate.confidence
            case .learning, .low, nil: nil
            }
        case .learning, .unavailable:
            nil
        }
        self.odometerKilometers = odometerKilometers
        self.odometerIsRetained = odometerKilometers != nil && vehicleState.connection != .connected
        self.rideStatus = rides.status
        self.dailyStatus = daily.status
        self.todayDistanceSummary = daily.todayAndCurrent?.today.distanceMeters
        self.currentRideDurationSummary = daily.todayAndCurrent?.currentRide?.durationSeconds
        self.isAutomaticCaptureEnabled = automaticCapture.isAutomaticCaptureEnabled
        self.canCaptureRideTelemetryWithoutOpeningApp = automaticCapture.readiness
            .canCaptureRideTelemetryWithoutOpeningApp
    }
}

struct DashboardBatteryRenderState: Equatable {
    let mode: NembraCore.BatteryPrimaryReadoutMode
    let primaryText: String
    let fillFraction: CGFloat?
    let adaptiveRangeConfidence: NembraCore.AdaptiveRangeConfidence?
    let isRetained: Bool
    let isLow: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String

    init(
        presentation: NembraCore.BatteryPrimaryReadoutPresentation,
        dataAvailability: VehicleDataAvailability,
        adaptiveRangeConfidence: NembraCore.AdaptiveRangeConfidence?
    ) {
        mode = presentation.mode
        fillFraction = presentation.batteryFillPercent.map { CGFloat($0) / 100 }
        self.adaptiveRangeConfidence = switch (presentation.mode, adaptiveRangeConfidence) {
        case (.estimatedRange, .normal), (.estimatedRange, .high): adaptiveRangeConfidence
        case (.percentage, _), (.estimatedRange, .learning), (.estimatedRange, .low), (.estimatedRange, nil): nil
        }
        isRetained = dataAvailability == .retained
        isLow = dataAvailability == .live
            && presentation.batteryFillPercent.map { $0 <= 15 } == true

        let retainedPrefix = isRetained ? "Last known. " : ""
        // VoiceOver follows the same one-value rule as the visual instrument.
        // Percentage mode already announces numeric SOC as its primary; range
        // mode describes fill truth without duplicating that alternate number.
        let fillTruth = if presentation.batteryFillPercent != nil {
            isRetained
                ? "Fill represents last known state of charge."
                : "Fill represents state of charge."
        } else {
            "State-of-charge fill unavailable."
        }
        switch presentation.primaryValue {
        case let .percentage(percent):
            primaryText = "\(percent)%"
            accessibilityValue = "\(retainedPrefix)\(percent) percent. \(fillTruth)"

        case let .estimatedRangeMeters(meters):
            let range = VehicleDisplayFormatting.distance(kilometers: meters / 1_000, decimals: 1)
            let confidence = switch self.adaptiveRangeConfidence {
            case .normal: "Normal confidence. "
            case .high: "High confidence. "
            case .learning, .low, nil: ""
            }
            primaryText = range
            accessibilityValue = "\(range), learned from accepted range-learning evidence. \(confidence)\(fillTruth)"

        case .learningRange:
            primaryText = "Learning"
            accessibilityValue = "Learning from accepted range-learning evidence. \(fillTruth)"

        case .unavailable:
            primaryText = "Unavailable"
            accessibilityValue = switch presentation.mode {
            case .percentage:
                "Battery unavailable until display-authoritative state-of-charge evidence exists. \(fillTruth)"
            case .estimatedRange:
                "Adaptive range unavailable until accepted evidence exists. \(fillTruth)"
            }
        }

        switch presentation.mode {
        case .percentage:
            accessibilityLabel = "Battery"
            accessibilityHint = "Double tap for adaptive range. The fill always represents state of charge."
        case .estimatedRange:
            accessibilityLabel = "Adaptive range"
            accessibilityHint = "Double tap for battery percentage. The fill always represents state of charge."
        }
    }
}

enum DashboardRideDurationFormatting {
    /// A mounted-phone glance surface must not attempt an unbounded integer
    /// conversion or render an arbitrarily wide duration. Values beyond
    /// 99:59:59 remain available in durable ride data, but this compact Drive
    /// projection fails closed until a wider presentation is explicitly designed.
    static let maximumDisplaySeconds = 359_999.999

    static func text(seconds: Double?) -> String {
        guard let seconds,
              seconds.isFinite,
              seconds >= 0,
              seconds <= maximumDisplaySeconds else { return "—" }

        let roundedSeconds = Int(seconds.rounded(.down))
        let hours = roundedSeconds / 3_600
        let minutes = (roundedSeconds % 3_600) / 60
        let remainingSeconds = roundedSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
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
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(emphasized ? NembraColor.gold : NembraColor.primaryText.opacity(0.82))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }

        return Group {
            if reduceTransparency {
                button
                    .buttonStyle(.plain)
                    .background {
                        Circle()
                            .fill(NembraColor.warmGraphite)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        emphasized ? NembraColor.gold.opacity(0.44) : Color.white.opacity(0.22),
                                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                                    )
                            }
                    }
            } else {
                button
                    .buttonStyle(.glass)
                    .tint(NembraColor.warmGraphite)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                emphasized ? NembraColor.gold.opacity(0.34) : Color.white.opacity(0.18),
                                lineWidth: colorSchemeContrast == .increased ? 1.4 : 0.8
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            }
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("dashboard.control.\(title.lowercased())")
    }
}

@MainActor
private struct DashboardDriveSlowLayer: View, @MainActor Equatable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(NembraPreferenceKey.haptics) private var hapticsEnabled = true

    let snapshot: DashboardDriveSnapshot
    let cockpit: HorizonCockpitStore
    let layout: DashboardDriveSlowLayout

    static func == (lhs: DashboardDriveSlowLayer, rhs: DashboardDriveSlowLayer) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.cockpit === rhs.cockpit
            && lhs.layout == rhs.layout
    }

    var body: some View {
        VStack(spacing: 0) {
            topChrome
            Spacer(minLength: 0)
            rideLedger
        }
        .padding(.leading, layout.safeAreaLeading + layout.horizontalPadding)
        .padding(.trailing, layout.safeAreaTrailing + layout.horizontalPadding)
        .padding(.top, layout.topPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(width: layout.viewportWidth, height: layout.viewportHeight)
    }

    private var topChrome: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top, spacing: 12) {
                    batteryControl
                        .layoutPriority(2)

                    Spacer(minLength: 12)

                    vehicleIdentity
                        .frame(maxWidth: 150)
                        .padding(.trailing, 108)
                }
            } else {
                ZStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 12) {
                        batteryControl
                            .layoutPriority(2)

                        Spacer(minLength: 190)
                    }

                    vehicleIdentity
                        .frame(maxWidth: 210)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 86 : 54)
    }

    private var rideLedger: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityRideLedger
            } else {
                ViewThatFits(in: .horizontal) {
                    standardRideLedger
                    compactRideLedger
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 108 : 62)
    }

    private var accessibilityRideLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            recordingStatus
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 8) {
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
                    Text(dynamicTypeSize.isAccessibilitySize ? "QA" : "QA ONLY")
                        .font(.caption2.weight(.bold))
                        .tracking(dynamicTypeSize.isAccessibilitySize ? 0.2 : 0.7)
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
        let renderState = DashboardBatteryRenderState(
            presentation: snapshot.batteryPresentation,
            dataAvailability: snapshot.batteryDataAvailability,
            adaptiveRangeConfidence: snapshot.adaptiveRangeConfidence
        )

        return Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                cockpit.toggleBatteryPrimaryReadout()
            }
        } label: {
            DashboardBatteryInstrument(
                fillFraction: renderState.fillFraction,
                label: renderState.primaryText,
                isRetained: renderState.isRetained,
                isLow: renderState.isLow,
                adaptiveRangeConfidence: renderState.adaptiveRangeConfidence,
                reduceMotion: reduceMotion
            )
            .frame(
                width: dynamicTypeSize.isAccessibilitySize ? 190 : 176,
                height: dynamicTypeSize.isAccessibilitySize ? 52 : 48
            )
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(
            .selection,
            trigger: snapshot.batteryPresentation.mode
        ) { _, _ in
            hapticsEnabled
        }
        .accessibilityLabel(renderState.accessibilityLabel)
        .accessibilityValue(qualifiedForSimulator(renderState.accessibilityValue))
        .accessibilityHint(renderState.accessibilityHint)
        .accessibilityIdentifier("dashboard.battery-range")
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
            Group {
                if differentiateWithoutColor {
                    Image(systemName: recordingStatusSymbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(recordingStatusColor)
                } else {
                    Circle()
                        .strokeBorder(recordingStatusColor, lineWidth: 2)
                }
            }
            .frame(width: 12, height: 12)
            .padding(.top, 3)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(recordingStatusTitle)
                    .font(
                        dynamicTypeSize.isAccessibilitySize
                            ? .caption2.weight(.semibold)
                            : .caption.weight(.semibold)
                    )
                    .foregroundStyle(NembraColor.primaryText.opacity(0.80))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                Text(recordingStatusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
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
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .caption2.weight(.bold)
                        : .system(size: 9, weight: .bold)
                )
                .tracking(dynamicTypeSize.isAccessibilitySize ? 0.4 : 1.6)
                .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            Text(value)
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .caption.weight(.semibold).monospacedDigit()
                        : .callout.weight(.semibold).monospacedDigit()
                )
                .foregroundStyle(value == "—" ? NembraColor.secondaryText : NembraColor.primaryText.opacity(0.78))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            if let qualifier {
                Text(qualifier)
                    .font(
                        dynamicTypeSize.isAccessibilitySize
                            ? .caption2.weight(.bold)
                            : .system(size: 8, weight: .bold)
                    )
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0.2 : 0.7)
                    .foregroundStyle(NembraColor.secondaryText.opacity(0.88))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(qualifiedForSimulator(metricAccessibilityValue(value: value, qualifier: qualifier)))
        .accessibilityIdentifier(identifier)
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
        DashboardRideDurationFormatting.text(seconds: currentRideDurationSummary?.value)
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
            "Accepted progress is checkpointed to Today"
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
            return NembraColor.secondaryText.opacity(0.88)
        case .idle:
            return snapshot.canCaptureRideTelemetryWithoutOpeningApp
                ? NembraColor.gold.opacity(0.82)
                : NembraColor.secondaryText.opacity(0.88)
        }
    }

    private var recordingStatusSymbol: String {
        switch snapshot.rideStatus {
        case .persistenceUnavailable, .failed:
            "exclamationmark.triangle.fill"
        case .restoring, .temporarilyDisconnected:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .candidate, .endingCandidate:
            "location.north.circle.fill"
        case .active:
            "record.circle.fill"
        case .saving:
            "checkmark.circle.fill"
        case .disabled, .idle:
            "circle"
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
        return base
    }

    private var connectionColor: Color {
        switch snapshot.connection {
        case .connected: .green
        case .connecting, .reconnecting: NembraColor.gold
        case .disconnected: NembraColor.secondaryText.opacity(0.88)
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
    @ScaledMetric(relativeTo: .headline) private var primaryFontSize: CGFloat = 19
    @ScaledMetric(relativeTo: .subheadline) private var longValueFontSize: CGFloat = 14

    let fillFraction: CGFloat?
    let label: String
    let isRetained: Bool
    let isLow: Bool
    let adaptiveRangeConfidence: NembraCore.AdaptiveRangeConfidence?
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                    drawBattery(context: &context, size: size)
                }
                .shadow(color: .black.opacity(0.72), radius: 7, y: 5)
                .shadow(
                    color: energyColor.opacity(reduceTransparency ? 0.055 : 0.13),
                    radius: 10,
                    x: -2,
                    y: 2
                )

                instrumentLabel(color: NembraColor.primaryText)
                    .frame(width: proxy.size.width - 30, height: proxy.size.height)

                if !isLow, let chargeMaskWidth = chargeMaskWidth(for: proxy.size) {
                    instrumentLabel(color: Color.black.opacity(0.86))
                        .frame(width: proxy.size.width - 30, height: proxy.size.height)
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: chargeMaskWidth)
                        }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func instrumentLabel(color: Color) -> some View {
        Text(label)
            .font(.system(
                size: label.count > 6
                    ? min(longValueFontSize, 20)
                    : min(primaryFontSize, 26),
                weight: .semibold,
                design: .default
            ))
            .fontWidth(.expanded)
            .monospacedDigit()
            .tracking(label.count > 6 ? 0.1 : 0.5)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .contentTransition(reduceMotion ? .identity : .opacity)
    }

    /// The dark duplicate is clipped to the exact SOC charge edge so copy gains
    /// contrast over gold without carving a permanent graphite well through the
    /// energy fill. The visible fill therefore remains one continuous SOC region.
    private func chargeMaskWidth(for size: CGSize) -> CGFloat? {
        guard let fillFraction else { return nil }
        let clamped = min(max(fillFraction, 0), 1)
        let terminalWidth = min(11, size.width * 0.065)
        let reservoirMinX: CGFloat = 5
        let reservoirWidth = max(0, size.width - terminalWidth - 11)
        let labelLeft: CGFloat = 15
        let labelWidth = max(0, size.width - 30)
        let chargeEnd = reservoirMinX + reservoirWidth * clamped
        return min(labelWidth, max(0, chargeEnd - labelLeft))
    }

    private var energyColor: Color {
        isLow ? .red : NembraColor.gold
    }

    private var chargeGradient: Gradient {
        if isLow {
            return Gradient(stops: [
                .init(color: Color(red: 0.48, green: 0.025, blue: 0.035), location: 0),
                .init(color: Color(red: 0.90, green: 0.11, blue: 0.10), location: 0.68),
                .init(color: Color(red: 1.00, green: 0.34, blue: 0.24), location: 1)
            ])
        }
        return Gradient(stops: [
            .init(color: NembraColor.deepGold.opacity(0.90), location: 0),
            .init(color: NembraColor.activeGold, location: 0.46),
            .init(color: NembraColor.gold, location: 0.82),
            .init(color: Color(red: 1.00, green: 0.82, blue: 0.39), location: 1)
        ])
    }

    private func drawBattery(context: inout GraphicsContext, size: CGSize) {
        guard size.width > 60, size.height > 24 else { return }

        let terminalWidth = min(11, size.width * 0.065)
        let bodyWidth = size.width - terminalWidth - 1
        let outerRect = CGRect(x: 0, y: 1, width: bodyWidth, height: size.height - 2)
        let outerRadius = min(11, outerRect.height * 0.23)
        let outerPath = RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
            .path(in: outerRect)
        let shellGradient = Gradient(stops: [
            .init(color: Color.white.opacity(reduceTransparency ? 0.33 : 0.22), location: 0),
            .init(color: Color(red: 0.17, green: 0.19, blue: 0.22), location: 0.22),
            .init(color: Color(red: 0.055, green: 0.062, blue: 0.071), location: 0.62),
            .init(color: Color.black.opacity(0.96), location: 1)
        ])

        let terminalRect = CGRect(
            x: outerRect.maxX - 2.5,
            y: size.height * 0.30,
            width: terminalWidth + 2.5,
            height: size.height * 0.40
        )
        let terminalPath = RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .path(in: terminalRect)
        context.fill(
            terminalPath,
            with: .linearGradient(
                shellGradient,
                startPoint: CGPoint(x: terminalRect.midX, y: terminalRect.minY),
                endPoint: CGPoint(x: terminalRect.midX, y: terminalRect.maxY)
            )
        )
        context.fill(
            outerPath,
            with: .linearGradient(
                shellGradient,
                startPoint: CGPoint(x: outerRect.midX, y: outerRect.minY),
                endPoint: CGPoint(x: outerRect.midX, y: outerRect.maxY)
            )
        )

        let innerRect = outerRect.insetBy(dx: 2.5, dy: 2.5)
        let innerPath = RoundedRectangle(cornerRadius: max(6, outerRadius - 2.5), style: .continuous)
            .path(in: innerRect)
        context.fill(
            innerPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.055, green: 0.062, blue: 0.071), location: 0),
                    .init(color: Color(red: 0.016, green: 0.019, blue: 0.024), location: 0.50),
                    .init(color: .black, location: 1)
                ]),
                startPoint: CGPoint(x: innerRect.midX, y: innerRect.minY),
                endPoint: CGPoint(x: innerRect.midX, y: innerRect.maxY)
            )
        )

        let reservoirRect = innerRect.insetBy(dx: 2.5, dy: 2.5)
        let reservoirPath = RoundedRectangle(cornerRadius: max(5, outerRadius - 5), style: .continuous)
            .path(in: reservoirRect)
        context.fill(reservoirPath, with: .color(Color(red: 0.012, green: 0.015, blue: 0.019)))

        drawCharge(context: &context, reservoirRect: reservoirRect, reservoirPath: reservoirPath)
        drawRangeConfidence(context: &context, reservoirRect: reservoirRect)

        context.stroke(
            reservoirPath,
            with: .color(Color.white.opacity(colorSchemeContrast == .increased ? 0.42 : 0.18)),
            style: StrokeStyle(lineWidth: colorSchemeContrast == .increased ? 1.2 : 0.7)
        )
        context.stroke(
            outerPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(colorSchemeContrast == .increased ? 0.68 : 0.38), location: 0),
                    .init(color: Color.white.opacity(0.10), location: 0.45),
                    .init(color: Color.black.opacity(0.80), location: 1)
                ]),
                startPoint: CGPoint(x: outerRect.midX, y: outerRect.minY),
                endPoint: CGPoint(x: outerRect.midX, y: outerRect.maxY)
            ),
            style: StrokeStyle(lineWidth: colorSchemeContrast == .increased ? 1.3 : 0.9)
        )

        let terminalInnerRect = terminalRect.insetBy(dx: 2.2, dy: 2.2)
        let terminalInnerPath = RoundedRectangle(cornerRadius: 1.8, style: .continuous)
            .path(in: terminalInnerRect)
        context.fill(
            terminalInnerPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.12, green: 0.13, blue: 0.15),
                    Color.black.opacity(0.96)
                ]),
                startPoint: CGPoint(x: terminalInnerRect.midX, y: terminalInnerRect.minY),
                endPoint: CGPoint(x: terminalInnerRect.midX, y: terminalInnerRect.maxY)
            )
        )

        let shoulderRect = CGRect(
            x: outerRect.maxX - 3.5,
            y: terminalRect.minY + 2,
            width: 7,
            height: terminalRect.height - 4
        )
        var shoulder = Path()
        shoulder.addRect(shoulderRect)
        context.fill(
            shoulder,
            with: .linearGradient(
                shellGradient,
                startPoint: CGPoint(x: shoulderRect.midX, y: shoulderRect.minY),
                endPoint: CGPoint(x: shoulderRect.midX, y: shoulderRect.maxY)
            )
        )
    }

    private func drawCharge(
        context: inout GraphicsContext,
        reservoirRect: CGRect,
        reservoirPath: Path
    ) {
        guard let fillFraction else { return }
        let clamped = min(max(fillFraction, 0), 1)
        let fillWidth = reservoirRect.width * clamped
        guard fillWidth > 0.5 else { return }

        let fillRect = CGRect(
            x: reservoirRect.minX,
            y: reservoirRect.minY,
            width: fillWidth,
            height: reservoirRect.height
        )
        let fillPath = RoundedRectangle(
            cornerRadius: min(7, max(2.5, fillWidth * 0.5)),
            style: .continuous
        ).path(in: fillRect)
        var chargeContext = context
        chargeContext.opacity = isRetained ? 0.72 : 1
        chargeContext.clip(to: reservoirPath)
        chargeContext.fill(
            fillPath,
            with: .linearGradient(
                chargeGradient,
                startPoint: CGPoint(x: fillRect.minX, y: fillRect.midY),
                endPoint: CGPoint(x: fillRect.maxX, y: fillRect.midY)
            )
        )
        chargeContext.clip(to: fillPath)

        var highlight = Path()
        highlight.addRect(fillRect)
        chargeContext.fill(
            highlight,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.24), location: 0),
                    .init(color: Color.white.opacity(0.055), location: 0.42),
                    .init(color: Color.black.opacity(0.15), location: 1)
                ]),
                startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)
            )
        )

        var ribs = Path()
        for x in stride(from: fillRect.minX + 2, through: fillRect.maxX - 1, by: 3.5) {
            ribs.move(to: CGPoint(x: x, y: fillRect.minY + 2))
            ribs.addLine(to: CGPoint(x: x, y: fillRect.maxY - 2))
        }
        chargeContext.stroke(
            ribs,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.22), location: 0),
                    .init(color: Color.white.opacity(0.075), location: 0.48),
                    .init(color: Color.black.opacity(0.18), location: 1)
                ]),
                startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)
            ),
            style: StrokeStyle(lineWidth: 0.55)
        )
    }

    private func drawRangeConfidence(
        context: inout GraphicsContext,
        reservoirRect: CGRect
    ) {
        let count: Int = switch adaptiveRangeConfidence {
        case .normal: 2
        case .high: 3
        case .learning, .low, nil: 0
        }
        guard count > 0 else { return }

        var ticks = Path()
        let spacing: CGFloat = 3.2
        let startX = reservoirRect.maxX - CGFloat(count - 1) * spacing - 3
        for index in 0..<count {
            let x = startX + CGFloat(index) * spacing
            ticks.move(to: CGPoint(x: x, y: reservoirRect.maxY - 4.5))
            ticks.addLine(to: CGPoint(x: x, y: reservoirRect.maxY - 2.2))
        }
        context.stroke(
            ticks,
            with: .color(Color.white.opacity(0.82)),
            style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
        )
    }
}
