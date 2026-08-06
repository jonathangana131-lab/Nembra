import Foundation
import SwiftUI

/// The dedicated landscape riding surface.
///
/// Phase 9 intentionally renders only values already confirmed in `VehicleState`.
/// Raw-packet interpolation and rolling instrumentation are a separate Phase 10
/// presentation layer so this cockpit cannot accidentally turn animation into
/// telemetry evidence.
struct DashboardView: View {
    @Environment(VehicleStore.self) private var vehicle
    @State private var showLockConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topStatusRow

                Spacer(minLength: 8)

                speedInstrument

                Spacer(minLength: 8)

                bottomInstrumentRow
            }
            .safeAreaPadding(.horizontal, 28)
            .safeAreaPadding(.vertical, 18)
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

    private var topStatusRow: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.profile.identity.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Label(connectionText, systemImage: connectionIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connectionStyle)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard.vehicle-status")

            Spacer(minLength: 0)

            modeReadout
        }
    }

    private var speedInstrument: some View {
        VStack(spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(speedValueText)
                    .font(.system(size: 166, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)

                Text(speedUnitText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue(speedAccessibilityValue)
            .accessibilityIdentifier("dashboard.speed")

            liveStateCaption
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var liveStateCaption: some View {
        if vehicle.state.dataAvailability == .retained {
            Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                .font(.caption2.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(.secondary)
        } else if vehicle.state.connection == .connected {
            Text(isVehicleMoving ? "RIDING" : "READY")
                .font(.caption2.weight(.bold))
                .tracking(2.4)
                .foregroundStyle(.secondary)
        } else {
            Text("NO LIVE SPEED")
                .font(.caption2.weight(.bold))
                .tracking(2.2)
                .foregroundStyle(.secondary)
        }
    }

    private var bottomInstrumentRow: some View {
        HStack(alignment: .bottom, spacing: 34) {
            dashboardMetric(
                title: "BATTERY",
                value: batteryText,
                symbol: batteryIcon,
                warning: isBatteryLow,
                identifier: "dashboard.battery"
            )

            dashboardMetric(
                title: "TRIP",
                value: tripText,
                symbol: "point.bottomleft.forward.to.point.topright.scurvepath",
                identifier: "dashboard.trip"
            )

            Spacer(minLength: 24)

            if shouldShowStoppedControls {
                stoppedControls
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if shouldShowMovingReadout {
                movingStateReadout
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.20), value: shouldShowStoppedControls)
    }

    private var modeReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("MODE")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)

            Text(vehicle.state.rideMode?.displayName.uppercased() ?? "—")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride mode")
        .accessibilityValue(vehicle.state.rideMode?.displayName ?? "Unknown")
        .accessibilityIdentifier("dashboard.mode")
    }

    private var movingStateReadout: some View {
        HStack(spacing: 18) {
            if vehicle.profile.capabilities.supportsHeadlight,
               let isOn = vehicle.state.isHeadlightOn {
                Label(isOn ? "LIGHT ON" : "LIGHT OFF", systemImage: isOn ? "lightbulb.fill" : "lightbulb")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Headlight")
                    .accessibilityValue(isOn ? "On" : "Off")
                    .accessibilityIdentifier("dashboard.state.light")
            }

            if vehicle.profile.capabilities.supportsLock,
               let isLocked = vehicle.state.isLocked {
                Label(isLocked ? "LOCKED" : "UNLOCKED", systemImage: isLocked ? "lock.fill" : "lock.open")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lock status")
                    .accessibilityValue(isLocked ? "Locked" : "Unlocked")
                    .accessibilityIdentifier("dashboard.state.lock")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    private var stoppedControls: some View {
        HStack(spacing: 10) {
            if !supportedModes.isEmpty {
                modeSelector
            }

            if vehicle.profile.capabilities.supportsHeadlight,
               let isOn = vehicle.state.isHeadlightOn {
                Button {
                    Task { await vehicle.setHeadlight(!isOn) }
                } label: {
                    ZStack {
                        if vehicle.pendingCommands.contains(.headlight) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                        }
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.glass)
                .disabled(vehicle.isVehicleCommandPending)
                .accessibilityLabel(isOn ? "Turn light off" : "Turn light on")
                .accessibilityValue(isOn ? "On" : "Off")
                .accessibilityIdentifier("dashboard.control.light")
            }

            if vehicle.profile.capabilities.supportsLock,
               let isLocked = vehicle.state.isLocked {
                Button {
                    showLockConfirmation = true
                } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.glass)
                .disabled(vehicle.isVehicleCommandPending)
                .accessibilityLabel(isLocked ? "Unlock scooter" : "Lock scooter")
                .accessibilityValue(isLocked ? "Secured" : "Ready")
                .accessibilityIdentifier("dashboard.control.lock")
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(supportedModes, id: \.self) { mode in
                Button {
                    Task { await vehicle.setMode(mode) }
                } label: {
                    ZStack {
                        if vehicle.state.rideMode == mode {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.white.opacity(0.14))
                                .padding(3)
                        }

                        if vehicle.pendingRideMode == mode {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text(modeAbbreviation(mode))
                                .font(.caption.weight(vehicle.state.rideMode == mode ? .bold : .semibold))
                                .foregroundStyle(vehicle.state.rideMode == mode ? .white : .secondary)
                        }
                    }
                    .frame(width: 44, height: 42)
                }
                .buttonStyle(.plain)
                .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending)
                .accessibilityLabel(mode.displayName)
                .accessibilityIdentifier("dashboard.mode.\(mode.displayName.lowercased())")
            }
        }
        .padding(2)
        .background {
            Capsule(style: .continuous)
                .fill(.white.opacity(0.065))
        }
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ride mode controls")
    }

    private func dashboardMetric(
        title: String,
        value: String,
        symbol: String,
        warning: Bool = false,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(warning ? Color.red : Color.secondary)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(warning ? Color.red : Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { vehicle.lastErrorMessage != nil },
            set: { if !$0 { vehicle.lastErrorMessage = nil } }
        )
    }

    private var shouldShowStoppedControls: Bool {
        vehicle.state.connection == .connected && !isVehicleMoving
    }

    private var shouldShowMovingReadout: Bool {
        vehicle.state.connection == .connected && isVehicleMoving
    }

    private var isVehicleMoving: Bool {
        (vehicle.state.speedKilometersPerHour ?? 0) >= 0.5
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

    private var speedValueText: String {
        guard let kilometersPerHour = vehicle.state.speedKilometersPerHour else { return "—" }
        let value = VehicleDisplayFormatting.usesMetric ? kilometersPerHour : kilometersPerHour * 0.621_371
        return String(format: "%.0f", max(0, value))
    }

    private var speedUnitText: String {
        VehicleDisplayFormatting.usesMetric ? "KM/H" : "MPH"
    }

    private var speedAccessibilityValue: String {
        VehicleDisplayFormatting.speed(kilometersPerHour: vehicle.state.speedKilometersPerHour)
    }

    private var tripText: String {
        VehicleDisplayFormatting.distance(kilometers: vehicle.state.tripKilometers)
    }

    private var batteryText: String {
        guard let battery = vehicle.state.batteryPercent else { return "—" }
        return "\(battery)%"
    }

    private var isBatteryLow: Bool {
        guard let battery = vehicle.state.batteryPercent else { return false }
        return battery <= 15
    }

    private var batteryIcon: String {
        guard let battery = vehicle.state.batteryPercent else { return "battery.0percent" }
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
}
