import Dispatch
import Foundation
import SwiftUI

/// Pure presentation state for the landscape cockpit.
///
/// Mode personality is deliberately visual-only. It never changes speed,
/// telemetry, command behavior, speed limits, or ride evidence, and it does not
/// imply any unverified mapping between MAXSHOT ride modes and DP101/102/103.
struct DashboardModePersonality: Equatable {
    let mode: RideMode?
    let ambientOpacity: Double
    let speedScale: CGFloat
    let modeScale: CGFloat
    let modeMarkerWidth: CGFloat
    let modeMarkerOpacity: Double
    let statusOpacity: Double

    static func resolved(for mode: RideMode?) -> DashboardModePersonality {
        switch mode {
        case .walk:
            DashboardModePersonality(mode: .walk, ambientOpacity: 0.018, speedScale: 0.96, modeScale: 0.97, modeMarkerWidth: 24, modeMarkerOpacity: 0.22, statusOpacity: 0.58)
        case .eco:
            DashboardModePersonality(mode: .eco, ambientOpacity: 0.030, speedScale: 0.98, modeScale: 0.99, modeMarkerWidth: 30, modeMarkerOpacity: 0.32, statusOpacity: 0.62)
        case .drive:
            DashboardModePersonality(mode: .drive, ambientOpacity: 0.044, speedScale: 1.0, modeScale: 1.0, modeMarkerWidth: 38, modeMarkerOpacity: 0.46, statusOpacity: 0.68)
        case .sport:
            DashboardModePersonality(mode: .sport, ambientOpacity: 0.062, speedScale: 1.025, modeScale: 1.03, modeMarkerWidth: 48, modeMarkerOpacity: 0.62, statusOpacity: 0.74)
        case nil:
            DashboardModePersonality(mode: nil, ambientOpacity: 0.012, speedScale: 1.0, modeScale: 1.0, modeMarkerWidth: 22, modeMarkerOpacity: 0.14, statusOpacity: 0.58)
        }
    }
}

private enum DashboardBatteryReadout: Equatable {
    case charge
    case range
}

/// Presentation-only layout policy. Accessibility sizes deliberately stop using
/// fixed side rails so large text cannot squeeze the central speed instrument.
private enum DashboardCockpitComposition: Equatable {
    case standard
    case accessibility

    static func resolved(for dynamicTypeSize: DynamicTypeSize) -> DashboardCockpitComposition {
        dynamicTypeSize.isAccessibilitySize ? .accessibility : .standard
    }
}

/// The dedicated landscape riding surface.
///
/// Battery/range intentionally has no synthetic range fallback. Until a verified
/// ES80 battery source and learned range model exist, range presents as unavailable
/// rather than deriving miles from advertised range or battery percentage.
struct DashboardView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showLockConfirmation = false
    @State private var batteryReadout: DashboardBatteryReadout = .charge

    var body: some View {
        let personality = DashboardModePersonality.resolved(for: vehicle.state.rideMode)
        let composition = DashboardCockpitComposition.resolved(for: dynamicTypeSize)

        ZStack {
            Color.black.ignoresSafeArea()

            if !reduceTransparency {
                RadialGradient(
                    colors: [Color.white.opacity(admittedAmbientOpacity(personality)), Color.clear],
                    center: .center,
                    startRadius: 18,
                    endRadius: 390
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(modeAnimation, value: personality)
            }

            Group {
                switch composition {
                case .standard:
                    standardCockpit(personality: personality)
                case .accessibility:
                    accessibilityCockpit(personality: personality)
                }
            }
            .safeAreaPadding(.horizontal, composition == .accessibility ? 14 : 20)
            .safeAreaPadding(.vertical, composition == .accessibility ? 8 : 12)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.cockpit")
        .confirmationDialog(
            vehicle.state.isLocked == true ? "Unlock scooter?" : "Lock scooter?",
            isPresented: $showLockConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                vehicle.state.isLocked == true ? "Unlock" : "Lock",
                role: vehicle.state.isLocked == true ? nil : .destructive
            ) {
                Task { await vehicle.setLocked(!(vehicle.state.isLocked ?? false)) }
            }
        } message: {
            Text("Nembra changes the lock state only after the scooter confirms the command.")
        }
        .alert("Command not confirmed", isPresented: errorPresented) {
            Button("OK", role: .cancel) { vehicle.lastErrorMessage = nil }
        } message: {
            Text(vehicle.lastErrorMessage ?? "The scooter did not confirm the change.")
        }
    }

    private func standardCockpit(personality: DashboardModePersonality) -> some View {
        HStack(spacing: 0) {
            statusRail
                .frame(width: 156)

            VStack(spacing: 0) {
                DashboardSpeedInstrumentView(modePersonality: personality)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                energyRailInstrument
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(2)

            contextRail(personality: personality)
                .frame(width: 176)
        }
    }

    /// The Timeline owns only the display clock. Source receipts enter the package
    /// runtime in `VehicleStore.apply`, never here. Reduced Motion pauses periodic
    /// display ticks; parent semantic/source changes can still redraw accepted state.
    private var energyRailInstrument: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { _ in
            NembraEnergyRailView(
                state: energyRailVisualState(
                    atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
                )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private func energyRailVisualState(
        atUptimeNanoseconds uptimeNanoseconds: UInt64
    ) -> NembraEnergyRailVisualState {
        guard let projection = vehicle.energyRailProjection(
            atUptimeNanoseconds: uptimeNanoseconds
        ) else {
            return .unavailable
        }
        return NembraEnergyRailVisualState(projection: projection)
    }

    private func accessibilityCockpit(personality: DashboardModePersonality) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                accessibilityStatusSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                modeReadout(personality: personality)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            DashboardSpeedInstrumentView(modePersonality: personality)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(3)

            accessibilityControlStrip
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityIdentifier("dashboard.cockpit.accessibility")
    }

    private var accessibilityStatusSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(vehicle.profile.identity.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Label(connectionText, systemImage: connectionIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connectionStyle)
                    .lineLimit(1)
            }

            HStack(spacing: 14) {
                compactAccessibilityMetric(
                    title: "Battery",
                    value: batteryText,
                    warning: batteryInstrumentWarning,
                    retained: isRetainedBatteryData
                )
                compactAccessibilityMetric(
                    title: "Trip",
                    value: tripText,
                    retained: isRetainedVehicleData
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.accessibility-status")
    }

    private func compactAccessibilityMetric(
        title: String,
        value: String,
        warning: Bool = false,
        retained: Bool = false
    ) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(warning ? Color.red : Color.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(warning ? Color.red : (retained ? Color.secondary : Color.white))
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(retained && value != "—" ? "Last known \(value)" : value)
    }

    @ViewBuilder
    private var accessibilityControlStrip: some View {
        if shouldShowStoppedControls {
            stoppedControls
                .transition(.opacity)
        } else if vehicle.state.connection == .connected && !hasUsableStoppedSpeed {
            Label("Live speed required for controls", systemImage: "speedometer")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Controls unavailable until current stopped speed is known")
                .accessibilityIdentifier("dashboard.controls-speed-unavailable-message")
        } else if isVehicleMoving {
            Text("Controls available when stopped")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier("dashboard.controls-moving-message")
        }
    }

    private var statusRail: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text(vehicle.profile.identity.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Label(connectionText, systemImage: connectionIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connectionStyle)
                    .lineLimit(1)

                dataStatusBadge
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("dashboard.vehicle-status")

            Spacer(minLength: 0)

            batteryRangeInstrument

            dashboardMetric(
                title: "TRIP",
                value: tripText,
                symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                retained: isRetainedVehicleData,
                identifier: "dashboard.trip"
            )
        }
    }

    private var batteryRangeInstrument: some View {
        Button {
            batteryReadout = batteryReadout == .charge ? .range : .charge
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: batteryReadout == .charge ? batteryIcon : "location.fill")
                    Text(batteryReadout == .charge ? "BATTERY" : "RANGE")
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(batteryInstrumentWarning ? Color.red : Color.secondary)

                Text(batteryPrimaryText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(batteryPrimaryColor)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                batteryChargeBar
                    .frame(width: 82)

                if isRetainedBatteryData, batteryPercent != nil {
                    Text("LAST KNOWN")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(.orange)
                } else if batteryReadout == .range {
                    Text("NOT CALIBRATED")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .sensoryFeedback(.selection, trigger: batteryReadout)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batteryReadout == .charge ? "Battery" : "Estimated range")
        .accessibilityValue(batteryAccessibilityValue)
        .accessibilityHint("Double tap to switch between battery charge and range. Range remains unavailable until Nembra has verified battery evidence and a learned range model.")
        .accessibilityIdentifier("dashboard.battery-range")
    }

    private var batteryChargeBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(colorSchemeContrast == .increased ? 0.22 : 0.10))

                if let fill = batteryFillFraction {
                    Capsule(style: .continuous)
                        .fill(batteryInstrumentWarning ? Color.red : Color.white.opacity(isRetainedBatteryData ? 0.48 : 0.92))
                        .frame(width: max(2, proxy.size.width * fill))
                }
            }
        }
        .frame(height: colorSchemeContrast == .increased ? 5 : 3)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var dataStatusBadge: some View {
        switch vehicle.state.dataAvailability {
        case .live:
            Label("LIVE DATA", systemImage: "wave.3.right")
                .foregroundStyle(colorSchemeContrast == .increased ? Color.white : Color.green)
                .accessibilityLabel("Vehicle data")
                .accessibilityValue("Live")
        case .retained:
            Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
                .accessibilityLabel("Vehicle data")
                .accessibilityValue("Last known values retained from the previous connection")
        case .unavailable:
            Label("WAITING FOR DATA", systemImage: "ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Vehicle data")
                .accessibilityValue("No confirmed scooter telemetry yet")
        }
    }

    private func contextRail(personality: DashboardModePersonality) -> some View {
        VStack(alignment: .trailing, spacing: 14) {
            modeReadout(personality: personality)
            Spacer(minLength: 0)

            if shouldShowStoppedControls {
                stoppedControls
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if vehicle.state.connection == .connected && !hasUsableStoppedSpeed {
                Label("Live speed required", systemImage: "speedometer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Controls unavailable until current stopped speed is known")
                    .accessibilityIdentifier("dashboard.controls-speed-unavailable-message")
            } else if isVehicleMoving {
                Text("Controls available when stopped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("dashboard.controls-moving-message")
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.20), value: shouldShowStoppedControls)
    }

    private func modeReadout(personality: DashboardModePersonality) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("MODE")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            Text(vehicle.state.rideMode?.displayName.uppercased() ?? "—")
                .font(.title2.weight(.semibold))
                .foregroundStyle(isRetainedVehicleData ? Color.secondary : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(colorSchemeContrast == .increased ? max(personality.modeMarkerOpacity, 0.62) : personality.modeMarkerOpacity))
                .frame(width: personality.modeMarkerWidth, height: colorSchemeContrast == .increased ? 3 : 2)
                .accessibilityHidden(true)

            if isRetainedVehicleData, vehicle.state.rideMode != nil {
                Text("LAST KNOWN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.orange)
            }
        }
        .scaleEffect(personality.modeScale, anchor: .trailing)
        .animation(modeAnimation, value: personality)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride mode")
        .accessibilityValue(modeAccessibilityValue)
        .accessibilityIdentifier("dashboard.mode")
    }

    private var stoppedControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !supportedModes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(supportedModes, id: \.self) { mode in
                        let isSelected = vehicle.state.rideMode == mode
                        let isPending = vehicle.pendingRideMode == mode

                        Button {
                            Task { await vehicle.setMode(mode) }
                        } label: {
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(.white.opacity(colorSchemeContrast == .increased ? 0.20 : 0.12))
                                }

                                if isPending {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Text(modeAbbreviation(mode))
                                        .font(.caption.weight(isSelected ? .bold : .semibold))
                                        .foregroundStyle(isSelected ? .white : .secondary)
                                }
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.glass)
                        .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending || isSelected)
                        .accessibilityLabel(mode.displayName)
                        .accessibilityValue(modeChoiceAccessibilityValue(selected: isSelected, pending: isPending))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("dashboard.mode.\(mode.displayName.lowercased())")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Ride mode controls")
            }

            HStack(spacing: 7) {
                if vehicle.profile.capabilities.supportsHeadlight,
                   let isOn = vehicle.state.isHeadlightOn {
                    let isPending = vehicle.pendingCommands.contains(.headlight)

                    Button {
                        Task { await vehicle.setHeadlight(!isOn) }
                    } label: {
                        ZStack {
                            if isPending {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(vehicle.isVehicleCommandPending)
                    .accessibilityLabel(isOn ? "Turn light off" : "Turn light on")
                    .accessibilityValue(isPending ? "Updating" : (isOn ? "On" : "Off"))
                    .accessibilityIdentifier("dashboard.control.light")
                }

                if vehicle.profile.capabilities.supportsLock,
                   let isLocked = vehicle.state.isLocked {
                    let isPending = vehicle.pendingCommands.contains(.lock)

                    Button {
                        showLockConfirmation = true
                    } label: {
                        ZStack {
                            if isPending {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: isLocked ? "lock.fill" : "lock.open")
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(vehicle.isVehicleCommandPending)
                    .accessibilityLabel(isLocked ? "Unlock scooter" : "Lock scooter")
                    .accessibilityValue(isPending ? "Updating" : (isLocked ? "Secured" : "Ready"))
                    .accessibilityIdentifier("dashboard.control.lock")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private func dashboardMetric(
        title: String,
        value: String,
        symbol: String,
        warning: Bool = false,
        retained: Bool = false,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(warning ? Color.red : Color.secondary)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(warning ? Color.red : (retained ? Color.secondary : Color.white))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if retained, value != "—" {
                Text("LAST KNOWN")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(retained && value != "—" ? "Last known \(value)" : value)
        .accessibilityIdentifier(identifier)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { vehicle.lastErrorMessage != nil },
            set: { if !$0 { vehicle.lastErrorMessage = nil } }
        )
    }

    /// Only source-qualified current speed may admit stopped-only controls. A cached
    /// aggregate speed can remain useful as retained display state, but it cannot
    /// establish that the scooter is currently stopped after a gap or reconnect.
    /// Physical/unverified profiles therefore remain unavailable until direct ES80
    /// evidence establishes a verified speed authority.
    private var usableStoppedControlSpeedKilometersPerHour: Double? {
        vehicle.simulatorQualifiedLiveSpeedKilometersPerHour
    }

    private var shouldShowStoppedControls: Bool {
        guard let speed = usableStoppedControlSpeedKilometersPerHour else { return false }
        return speed < 0.5
    }

    private var hasUsableStoppedSpeed: Bool {
        usableStoppedControlSpeedKilometersPerHour != nil
    }

    private var isVehicleMoving: Bool {
        guard let speed = usableStoppedControlSpeedKilometersPerHour else { return false }
        return speed >= 0.5
    }

    private var isRetainedVehicleData: Bool {
        vehicle.state.dataAvailability == .retained
    }

    private var isRetainedBatteryData: Bool {
        vehicle.batteryDataAvailability == .retained
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
    }

    private func modeAbbreviation(_ mode: RideMode) -> String {
        switch mode {
        case .walk: "W"
        case .eco: "E"
        case .drive: "D"
        case .sport: "S"
        }
    }

    private func modeChoiceAccessibilityValue(selected: Bool, pending: Bool) -> String {
        if pending { return "Updating" }
        return selected ? "Selected" : "Not selected"
    }

    private var modeAccessibilityValue: String {
        guard let mode = vehicle.state.rideMode?.displayName else { return "Unknown" }
        return isRetainedVehicleData ? "Last known \(mode)" : mode
    }

    private var tripText: String {
        VehicleDisplayFormatting.distance(kilometers: vehicle.state.tripKilometers)
    }

    private var batteryPercent: Int? {
        vehicle.batteryDisplayPercent
    }

    private var batteryText: String {
        guard let battery = batteryPercent else { return "—" }
        return "\(battery)%"
    }

    private var batteryPrimaryText: String {
        switch batteryReadout {
        case .charge: batteryText
        case .range: "—"
        }
    }

    private var batteryAccessibilityValue: String {
        switch batteryReadout {
        case .charge:
            if isRetainedBatteryData, batteryPercent != nil {
                return "Last known \(batteryText)"
            }
            if batteryPercent == nil {
                return "Unavailable until battery evidence is display-authoritative"
            }
            return batteryText
        case .range:
            return "Unavailable until a verified learned range model exists"
        }
    }

    private var batteryPrimaryColor: Color {
        if batteryInstrumentWarning { return .red }
        if isRetainedBatteryData { return .secondary }
        return batteryReadout == .range || batteryPercent == nil ? .secondary : .white
    }

    private var batteryInstrumentWarning: Bool {
        batteryReadout == .charge && isBatteryLow && !isRetainedBatteryData
    }

    private var batteryFillFraction: CGFloat? {
        guard let battery = batteryPercent else { return nil }
        return CGFloat(min(max(battery, 0), 100)) / 100
    }

    private var isBatteryLow: Bool {
        guard let battery = batteryPercent else { return false }
        return battery <= 15
    }

    private var batteryIcon: String {
        guard let battery = batteryPercent else { return "battery.0percent" }
        return switch battery {
        case ...15: "battery.0percent"
        case ...35: "battery.25percent"
        case ...60: "battery.50percent"
        case ...85: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var connectionText: String {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff: "Bluetooth Off"
            case .bluetoothPermissionDenied: "Permission Needed"
            case .scooterUnavailable: "Not Found"
            case .unsupportedConfiguration: "Unsupported"
            }
        } else {
            switch vehicle.state.connection {
            case .connected: "Connected"
            case .connecting: "Connecting"
            case .reconnecting: "Reconnecting"
            case .disconnected: "Offline"
            }
        }
    }

    private var connectionIcon: String {
        switch vehicle.state.connection {
        case .connected: "checkmark.circle.fill"
        case .connecting, .reconnecting: "antenna.radiowaves.left.and.right"
        case .disconnected: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var connectionStyle: Color {
        switch vehicle.state.connection {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .secondary
        }
    }

    private func admittedAmbientOpacity(_ personality: DashboardModePersonality) -> Double {
        let contrastMultiplier = colorSchemeContrast == .increased ? 0.35 : 1.0
        return personality.ambientOpacity * contrastMultiplier
    }

    private var modeAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.26)
    }
}
