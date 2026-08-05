import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @State private var showLockConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: NembraMetrics.major) {
                VehicleHeroView(profile: vehicle.profile, state: vehicle.state)

                if vehicle.state.connection != .connected {
                    connectionRecovery
                }

                primaryStatus
                quickControls
                vehicleDetails
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Nembra")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                connectionBadge
            }
        }
        .alert("Command not confirmed", isPresented: errorPresented) {
            Button("OK", role: .cancel) { vehicle.lastErrorMessage = nil }
        } message: {
            Text(vehicle.lastErrorMessage ?? "The scooter did not confirm the change.")
        }
        .confirmationDialog(
            vehicle.state.isLocked == true ? "Unlock scooter?" : "Lock scooter?",
            isPresented: $showLockConfirmation,
            titleVisibility: .visible
        ) {
            Button(vehicle.state.isLocked == true ? "Unlock" : "Lock", role: vehicle.state.isLocked == true ? nil : .destructive) {
                Task { await vehicle.setLocked(!(vehicle.state.isLocked ?? false)) }
            }
        } message: {
            Text("The state changes only after the scooter confirms the command.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { vehicle.lastErrorMessage != nil },
            set: { if !$0 { vehicle.lastErrorMessage = nil } }
        )
    }

    private var connectionRecovery: some View {
        let presentation = connectionRecoveryPresentation

        return HStack(spacing: 14) {
            Image(systemName: presentation.icon)
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(.headline)
                Text(presentation.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            switch presentation.action {
            case .progress:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(presentation.title)
            case .reconnect:
                Button {
                    Task { await vehicle.connect() }
                } label: {
                    if vehicle.pendingCommands.contains(.connect) {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.glass)
                .disabled(vehicle.pendingCommands.contains(.connect) || vehicle.isVehicleCommandPending)
                .accessibilityLabel("Reconnect scooter")
            case .settings:
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Image(systemName: "gear")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Open Nembra settings")
            case .none:
                EmptyView()
            }
        }
    }

    private var primaryStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if vehicle.state.connection != .connected && hasRetainedSummaryData {
                Label("Last known vehicle data", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHint("These values may be stale until the scooter reconnects.")
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    metric(title: "Battery", value: batteryText, systemImage: "battery.75percent")
                    Divider().frame(height: 42)
                    metric(title: "Trip", value: tripDistanceText, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", accessibilityTitle: "Scooter Trip")
                    Divider().frame(height: 42)
                    metric(title: "Mode", value: vehicle.state.rideMode?.displayName ?? "—", systemImage: "gauge.with.dots.needle.67percent")
                }

                VStack(spacing: 12) {
                    metric(title: "Battery", value: batteryText, systemImage: "battery.75percent")
                    Divider()
                    metric(title: "Trip", value: tripDistanceText, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath", accessibilityTitle: "Scooter Trip")
                    Divider()
                    metric(title: "Mode", value: vehicle.state.rideMode?.displayName ?? "—", systemImage: "gauge.with.dots.needle.67percent")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: NembraMetrics.group) {
            HStack {
                Text("Quick Controls")
                    .font(.title3.weight(.semibold))
                Spacer()
                NavigationLink("All Controls") {
                    VehicleControlsView()
                }
                .font(.subheadline.weight(.semibold))
            }

            if vehicle.profile.capabilities.supportsHeadlight || vehicle.profile.capabilities.supportsLock {
                HStack(spacing: 12) {
                    if vehicle.profile.capabilities.supportsHeadlight {
                        controlButton(
                            title: "Light",
                            icon: vehicle.state.isHeadlightOn == true ? "lightbulb.fill" : "lightbulb",
                            active: vehicle.state.isHeadlightOn == true,
                            pending: vehicle.pendingCommands.contains(.headlight),
                            available: vehicle.state.isHeadlightOn != nil
                        ) {
                            guard let isOn = vehicle.state.isHeadlightOn else { return }
                            Task { await vehicle.setHeadlight(!isOn) }
                        }
                    }

                    if vehicle.profile.capabilities.supportsLock {
                        controlButton(
                            title: vehicle.state.isLocked == true ? "Locked" : "Lock",
                            icon: vehicle.state.isLocked == true ? "lock.fill" : "lock.open",
                            active: vehicle.state.isLocked == true,
                            pending: vehicle.pendingCommands.contains(.lock),
                            available: vehicle.state.isLocked != nil
                        ) {
                            showLockConfirmation = true
                        }
                    }
                }
            }

            if !supportedModes.isEmpty {
                modeSelector
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(supportedModes, id: \.self) { mode in
                Button {
                    Task { await vehicle.setMode(mode) }
                } label: {
                    HStack(spacing: 5) {
                        Text(mode.displayName)
                            .font(.subheadline.weight(vehicle.state.rideMode == mode ? .semibold : .medium))
                        if vehicle.pendingRideMode == mode {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(vehicle.state.rideMode == mode ? .primary : .secondary)
                .background {
                    if vehicle.state.rideMode == mode {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.primary.opacity(0.08))
                    }
                }
                .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending)
            }
        }
        .padding(5)
        .nembraGlassControl()
        .accessibilityLabel("Ride mode")
    }

    @ViewBuilder
    private var vehicleDetails: some View {
        if !vehicleDetailItems.isEmpty {
            VStack(alignment: .leading, spacing: NembraMetrics.group) {
                Text("Vehicle")
                    .font(.title3.weight(.semibold))

                ForEach(vehicleDetailItems.indices, id: \.self) { index in
                    let item = vehicleDetailItems[index]
                    detailRow(title: item.title, value: item.value, icon: item.icon)
                    if index < vehicleDetailItems.index(before: vehicleDetailItems.endIndex) {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func controlButton(
        title: String,
        icon: String,
        active: Bool,
        pending: Bool,
        available: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if pending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(title).fontWeight(.semibold)
                Spacer()
                if active && !pending {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .nembraGlassControl()
        .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending || !available)
    }

    private func metric(title: String, value: String, systemImage: String, accessibilityTitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityTitle ?? title), \(value)")
    }

    private func detailRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.body)
        .accessibilityElement(children: .combine)
    }

    private var connectionBadge: some View {
        Label(connectionText, systemImage: connectionIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(vehicle.state.connection == .connected ? .green : .secondary)
            .accessibilityLabel("Scooter connection: \(connectionText)")
    }

    private enum ConnectionRecoveryAction {
        case progress
        case reconnect
        case settings
        case none
    }

    private struct ConnectionRecoveryPresentation {
        let title: String
        let message: String
        let icon: String
        let action: ConnectionRecoveryAction
    }

    private var connectionRecoveryPresentation: ConnectionRecoveryPresentation {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff:
                return ConnectionRecoveryPresentation(
                    title: "Bluetooth is off",
                    message: "Turn on Bluetooth to reconnect to your scooter.",
                    icon: "antenna.radiowaves.left.and.right.slash",
                    action: .none
                )
            case .bluetoothPermissionDenied:
                return ConnectionRecoveryPresentation(
                    title: "Bluetooth access is off",
                    message: "Allow Bluetooth access in Settings to connect to your scooter.",
                    icon: "hand.raised.fill",
                    action: .settings
                )
            case .scooterUnavailable:
                return ConnectionRecoveryPresentation(
                    title: "Scooter not found",
                    message: "Make sure it’s powered on and nearby, then try again.",
                    icon: "antenna.radiowaves.left.and.right.slash",
                    action: .reconnect
                )
            case .unsupportedConfiguration:
                return ConnectionRecoveryPresentation(
                    title: "Scooter software not recognized",
                    message: "Controls stay unavailable until this hardware or firmware is verified.",
                    icon: "exclamationmark.shield.fill",
                    action: .none
                )
            }
        }

        switch vehicle.state.connection {
        case .connecting:
            return ConnectionRecoveryPresentation(
                title: "Connecting to scooter",
                message: "Nembra is establishing a vehicle connection.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .reconnecting:
            return ConnectionRecoveryPresentation(
                title: "Trying to reconnect",
                message: "Your last confirmed vehicle state stays read-only while the link recovers.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .disconnected:
            return ConnectionRecoveryPresentation(
                title: "Scooter is offline",
                message: "Controls stay read-only until the vehicle connection is confirmed.",
                icon: "bolt.horizontal.circle",
                action: .reconnect
            )
        case .connected:
            return ConnectionRecoveryPresentation(
                title: "Connected",
                message: "Vehicle connection confirmed.",
                icon: "checkmark.circle",
                action: .none
            )
        }
    }

    private struct VehicleDetailItem {
        let title: String
        let value: String
        let icon: String
    }

    private var vehicleDetailItems: [VehicleDetailItem] {
        var items: [VehicleDetailItem] = []
        if vehicle.profile.capabilities.supportsOdometer {
            items.append(VehicleDetailItem(
                title: "Odometer",
                value: VehicleDisplayFormatting.distance(kilometers: vehicle.state.odometerKilometers),
                icon: "road.lanes"
            ))
        }
        if vehicle.profile.capabilities.supportsStartMode {
            items.append(VehicleDetailItem(
                title: "Start",
                value: vehicle.state.startMode?.displayName ?? "—",
                icon: "figure.walk.motion"
            ))
        }
        if vehicle.profile.capabilities.supportsCruise {
            items.append(VehicleDetailItem(
                title: "Cruise",
                value: cruiseText,
                icon: "gauge.open.with.lines.needle.33percent"
            ))
        }
        return items
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
    }

    private var hasRetainedSummaryData: Bool {
        guard vehicle.state.dataAvailability == .retained else { return false }
        return vehicle.state.batteryPercent != nil ||
            vehicle.state.tripKilometers != nil ||
            vehicle.state.rideMode != nil
    }

    private var batteryText: String {
        guard let value = vehicle.state.batteryPercent else { return "—" }
        return "\(value)%"
    }

    private var tripDistanceText: String {
        VehicleDisplayFormatting.distance(kilometers: vehicle.state.tripKilometers)
    }

    private var cruiseText: String {
        guard let enabled = vehicle.state.isCruiseEnabled else { return "—" }
        return enabled ? "On" : "Off"
    }

    private var connectionText: String {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff: return "Bluetooth Off"
            case .bluetoothPermissionDenied: return "Permission Needed"
            case .scooterUnavailable: return "Not Found"
            case .unsupportedConfiguration: return "Unsupported"
            }
        }

        switch vehicle.state.connection {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Offline"
        }
    }

    private var connectionIcon: String {
        if vehicle.state.connection == .connected { return "checkmark.circle.fill" }
        if vehicle.state.connection == .connecting || vehicle.state.connection == .reconnecting {
            return "antenna.radiowaves.left.and.right"
        }
        return "antenna.radiowaves.left.and.right.slash"
    }
}
