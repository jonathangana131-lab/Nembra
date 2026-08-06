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

            HStack(spacing: 0) {
                statusRail
                    .frame(width: 156)

                speedInstrument
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                contextRail
                    .frame(width: 176)
            }
            .safeAreaPadding(.horizontal, 20)
            .safeAreaPadding(.vertical, 12)
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

    private var statusRail: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        }
    }

    private var speedInstrument: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(speedValueText)
                    .font(.system(size: 148, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)

                Text(speedUnitText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 18)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue(speedAccessibilityValue)
            .accessibilityIdentifier("dashboard.speed")

            Group {
                if vehicle.state.dataAvailability == .retained {
                    Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                } else if vehicle.state.connection == .connected {
                    Text(isVehicleMoving ? "RIDING" : "READY")
                } else {
                    Text("NO LIVE SPEED")
                }
            }
            .font(.caption2.weight(.bold))
            .tracking(2.2)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
    }

    private var contextRail: some View {
        VStack(alignment: .trailing, spacing: 14) {
            modeReadout

            Spacer(minLength: 0)

            if shouldShowStoppedControls {
                stoppedControls
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if shouldShowMovingReadout {
                movingStateReadout
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.20), value: shouldShowStoppedControls)
    }

    private var modeReadout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("MODE")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
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
        VStack(alignment: .trailing, spacing: 9) {
            if vehicle.profile.capabilities.supportsHeadlight,
               let isOn = vehicle.state.isHeadlightOn {
                Label(isOn ? "LIGHT ON" : "LIGHT OFF", systemImage: isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isOn ? Color.white : Color.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Headlight")
                    .accessibilityValue(isOn ? "On" : "Off")
                    .accessibilityIdentifier("dashboard.state.light")
            }

            if vehicle.profile.capabilities.supportsLock,
               let isLocked = vehicle.state.isLocked {
                Label(isLocked ? "LOCKED" : "UNLOCKED", systemImage: isLocked ? "lock.fill" : "lock.open")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lock status")
                    .accessibilityValue(isLocked ? "Locked" : "Unlocked")
                    .accessibilityIdentifier("dashboard.state.lock")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    private var stoppedControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !supportedModes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(supportedModes, id: \.self) { mode in
                        Button {
                            Task { await vehicle.setMode(mode) }
                        } label: {
                            ZStack {
                                if vehicle.state.rideMode == mode {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(.white.opacity(0.12))
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
                            .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.glass)
                        .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending)
                        .accessibilityLabel(mode.displayName)
                        .accessibilityIdentifier("dashboard.mode.\(mode.displayName.lowercased())")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Ride mode controls")
            }

            HStack(spacing: 7) {
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
                        .frame(width: 36, height: 36)
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
                            .frame(width: 36, height: 36)
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
