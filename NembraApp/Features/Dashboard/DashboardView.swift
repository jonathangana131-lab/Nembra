import Foundation
import SwiftUI

struct DashboardView: View {
    @Environment(VehicleStore.self) private var vehicle
    @State private var showLockConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(spacing: 0) {
                statusRail
                    .frame(width: 172)

                speedInstrument
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                contextRail
                    .frame(width: 188)
            }
            .safeAreaPadding(.horizontal, 22)
            .safeAreaPadding(.vertical, 14)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
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
            Text("The state changes only after the scooter confirms the command.")
        }
        .alert("Command not confirmed", isPresented: errorPresented) {
            Button("OK", role: .cancel) { vehicle.lastErrorMessage = nil }
        } message: {
            Text(vehicle.lastErrorMessage ?? "The scooter did not confirm the change.")
        }
        .accessibilityIdentifier("dashboard.cockpit")
    }

    private var statusRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.profile.identity.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Label(connectionText, systemImage: connectionIcon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(connectionStyle)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            dashboardMetric(
                title: "BATTERY",
                value: batteryText,
                symbol: batteryIcon,
                warning: isBatteryLow
            )

            dashboardMetric(
                title: "TRIP",
                value: tripText,
                symbol: "point.bottomleft.forward.to.point.topright.scurvepath"
            )
        }
    }

    private var speedInstrument: some View {
        VStack(spacing: -2) {
            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(speedValueText)
                    .font(.system(size: 146, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .tracking(-7)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)

                Text(speedUnitText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 20)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Speed")
            .accessibilityValue(speedAccessibilityValue)
            .accessibilityIdentifier("dashboard.speed")

            if vehicle.state.dataAvailability == .retained {
                Label("Last known", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            } else if vehicle.state.connection == .connected {
                Text(isVehicleMoving ? "RIDING" : "READY")
                    .font(.caption2.weight(.bold))
                    .tracking(2.4)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var contextRail: some View {
        VStack(alignment: .trailing, spacing: 16) {
            modeReadout

            Spacer(minLength: 0)

            if shouldShowStoppedControls {
                stoppedControls
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else if isVehicleMoving {
                Text("Controls available when stopped")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .animation(.snappy(duration: 0.22), value: shouldShowStoppedControls)
    }

    private var modeReadout: some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text("MODE")
                .font(.caption2.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(.secondary)

            Text(vehicle.state.rideMode?.displayName.uppercased() ?? "—")
                .font(.title2.weight(.semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride mode")
        .accessibilityValue(vehicle.state.rideMode?.displayName ?? "Unknown")
        .accessibilityIdentifier("dashboard.mode")
    }

    private var stoppedControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !supportedModes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(supportedModes, id: \.self) { mode in
                        Button {
                            Task { await vehicle.setMode(mode) }
                        } label: {
                            Text(modeAbbreviation(mode))
                                .font(.caption.weight(vehicle.state.rideMode == mode ? .bold : .semibold))
                                .foregroundStyle(vehicle.state.rideMode == mode ? .white : .secondary)
                                .frame(width: 34, height: 34)
                                .background {
                                    if vehicle.state.rideMode == mode {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(.white.opacity(0.12))
                                    }
                                }
                        }
                        .buttonStyle(.glass)
                        .disabled(vehicle.isVehicleCommandPending)
                        .accessibilityLabel(mode.displayName)
                    }
                }
                .accessibilityLabel("Ride mode controls")
            }

            HStack(spacing: 7) {
                if vehicle.profile.capabilities.supportsHeadlight,
                   let isOn = vehicle.state.isHeadlightOn {
                    Button {
                        Task { await vehicle.setHeadlight(!isOn) }
                    } label: {
                        Image(systemName: isOn ? "lightbulb.fill" : "lightbulb")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .disabled(vehicle.isVehicleCommandPending)
                    .accessibilityLabel(isOn ? "Turn light off" : "Turn light on")
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
                }
            }
        }
    }

    private func dashboardMetric(
        title: String,
        value: String,
        symbol: String,
        warning: Bool = false
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
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.capitalized)
        .accessibilityValue(value)
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
