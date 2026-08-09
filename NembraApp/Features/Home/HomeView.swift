import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @State private var showLockConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                vehicleHeader

                if vehicle.state.connection != .connected {
                    connectionRecovery
                }

                statusPanel
                controlsSection

                if !supportedModes.isEmpty {
                    modeSection
                }

                vehicleSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Nembra")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    VehicleControlsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Vehicle controls")
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
            Button(
                vehicle.state.isLocked == true ? "Unlock" : "Lock",
                role: vehicle.state.isLocked == true ? nil : .destructive
            ) {
                Task { await vehicle.setLocked(!(vehicle.state.isLocked ?? false)) }
            }
        } message: {
            Text("Nembra changes the lock state only after the scooter confirms the command.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { vehicle.lastErrorMessage != nil },
            set: { if !$0 { vehicle.lastErrorMessage = nil } }
        )
    }

    private var vehicleHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(vehicle.profile.identity.displayName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)

                Label {
                    Text(vehicleStatusText)
                } icon: {
                    Circle()
                        .fill(connectionIndicatorColor)
                        .frame(width: 7, height: 7)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let isLocked = vehicle.state.isLocked {
                Label(isLocked ? "Locked" : "Unlocked", systemImage: isLocked ? "lock.fill" : "lock.open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isLocked ? .primary : .secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.055), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vehicle.state.connection != .connected && hasRetainedSummaryData {
                Label("Last known vehicle data", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHint("These values may be stale until the scooter reconnects.")
            }

            HStack(spacing: 0) {
                statusMetric(
                    title: "Battery",
                    value: batteryText,
                    icon: batteryIcon,
                    accessibilityIdentifier: "home.metric.battery",
                    valueStyle: batteryValueStyle
                )
                metricDivider
                statusMetric(
                    title: "Trip",
                    value: tripDistanceText,
                    icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                    accessibilityTitle: "Scooter Trip",
                    accessibilityIdentifier: "home.metric.trip"
                )
                metricDivider
                statusMetric(
                    title: "Mode",
                    value: vehicle.state.rideMode?.displayName ?? "—",
                    icon: "gauge.with.dots.needle.67percent",
                    accessibilityIdentifier: "home.metric.mode"
                )
            }
        }
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.primary.opacity(0.045))
        }
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 44)
            .padding(.horizontal, 12)
    }

    private func statusMetric(
        title: String,
        value: String,
        icon: String,
        accessibilityTitle: String? = nil,
        accessibilityIdentifier: String,
        valueStyle: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(title == "Battery" && isBatteryLow ? valueStyle : .secondary)
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueStyle)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(value)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Controls")

            HStack(spacing: 12) {
                if vehicle.profile.capabilities.supportsHeadlight {
                    actionControl(
                        title: "Light",
                        subtitle: lightSubtitle,
                        icon: vehicle.state.isHeadlightOn == true ? "lightbulb.fill" : "lightbulb",
                        active: vehicle.state.isHeadlightOn == true,
                        pending: vehicle.pendingCommands.contains(.headlight),
                        available: vehicle.state.isHeadlightOn != nil,
                        enabled: true
                    ) {
                        guard let isOn = vehicle.state.isHeadlightOn else { return }
                        Task { await vehicle.setHeadlight(!isOn) }
                    }
                }

                if vehicle.profile.capabilities.supportsLock {
                    actionControl(
                        title: lockControlTitle,
                        subtitle: lockSubtitle,
                        icon: vehicle.state.isLocked == true ? "lock.fill" : "lock.open",
                        active: vehicle.state.isLocked == true,
                        pending: vehicle.pendingCommands.contains(.lock),
                        available: vehicle.state.isLocked != nil,
                        enabled: canChangeLockState
                    ) {
                        showLockConfirmation = true
                    }
                }
            }
        }
    }

    private func actionControl(
        title: String,
        subtitle: String,
        icon: String,
        active: Bool,
        pending: Bool,
        available: Bool,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(active ? Color.primary.opacity(0.10) : Color.primary.opacity(0.055))
                        .frame(width: 36, height: 36)

                    if pending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(available ? subtitle : "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .nembraGlassControl()
        .disabled(
            vehicle.state.connection != .connected ||
            vehicle.isVehicleCommandPending ||
            !available ||
            !enabled
        )
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Ride Mode")

            HStack(spacing: 4) {
                ForEach(supportedModes, id: \.self) { mode in
                    Button {
                        Task { await vehicle.setMode(mode) }
                    } label: {
                        ZStack {
                            if vehicle.state.rideMode == mode {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                            }

                            HStack(spacing: 5) {
                                Text(mode.displayName)
                                    .font(.subheadline.weight(vehicle.state.rideMode == mode ? .semibold : .medium))

                                if vehicle.pendingRideMode == mode {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                            }
                            .foregroundStyle(vehicle.state.rideMode == mode ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending)
                    .accessibilityLabel(mode.displayName)
                    .accessibilityIdentifier("home.mode.\(mode.displayName.lowercased())")
                }
            }
            .padding(4)
            .background(
                Color.primary.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .sensoryFeedback(.selection, trigger: vehicle.state.rideMode)
    }

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Vehicle")

            VStack(spacing: 0) {
                ForEach(vehicleDetailItems.indices, id: \.self) { index in
                    let item = vehicleDetailItems[index]
                    detailRow(title: item.title, value: item.value, icon: item.icon)

                    if index < vehicleDetailItems.index(before: vehicleDetailItems.endIndex) {
                        Divider().padding(.leading, 42)
                    }
                }

                if !vehicleDetailItems.isEmpty {
                    Divider().padding(.leading, 42)
                }

                NavigationLink {
                    VehicleControlsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 26)
                            .foregroundStyle(.secondary)
                        Text("All Vehicle Controls")
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 48)
                }
            }
            .padding(.horizontal, 14)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func detailRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 26)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.body)
        .frame(minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private var connectionRecovery: some View {
        let presentation = connectionRecoveryPresentation

        return HStack(spacing: 12) {
            Image(systemName: presentation.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
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
                title: "Connecting",
                message: "Establishing a confirmed vehicle connection.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .reconnecting:
            return ConnectionRecoveryPresentation(
                title: "Reconnecting",
                message: "Last confirmed values stay read-only until the scooter returns.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .disconnected:
            return ConnectionRecoveryPresentation(
                title: "Scooter offline",
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

    private var lightSubtitle: String {
        guard let enabled = vehicle.state.isHeadlightOn else { return "Unknown" }
        return enabled ? "On" : "Off"
    }

    private var lockControlTitle: String {
        vehicle.state.isLocked == true ? "Unlock" : "Lock"
    }

    private var lockSubtitle: String {
        guard let locked = vehicle.state.isLocked else { return "Unknown" }
        if locked { return "Secured" }
        guard let speed = vehicle.simulatorQualifiedLiveSpeedKilometersPerHour else {
            return "Live speed required"
        }
        return speed >= 0.5 ? "Stop to lock" : "Ready"
    }

    private var canChangeLockState: Bool {
        vehicle.state.isLocked == true || vehicle.canLockFromCurrentSpeedEvidence
    }

    private var isBatteryLow: Bool {
        guard let battery = vehicle.state.batteryPercent else { return false }
        return battery <= 15
    }

    private var batteryIcon: String {
        guard let battery = vehicle.state.batteryPercent else { return "battery.0percent" }
        switch battery {
        case ...15: return "battery.0percent"
        case ...35: return "battery.25percent"
        case ...60: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var batteryValueStyle: Color {
        isBatteryLow ? .red : .primary
    }

    private var vehicleStatusText: String {
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
            if let speed = vehicle.simulatorQualifiedLiveSpeedKilometersPerHour, speed > 0.5 {
                return "Riding · \(VehicleDisplayFormatting.speed(kilometersPerHour: speed))"
            }
            return "Connected"
        case .connecting: return "Connecting"
        case .reconnecting: return "Reconnecting"
        case .disconnected: return "Offline"
        }
    }

    private var connectionIndicatorColor: Color {
        switch vehicle.state.connection {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .disconnected: .secondary
        }
    }
}
