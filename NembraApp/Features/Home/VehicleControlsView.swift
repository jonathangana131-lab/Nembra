import SwiftUI
import UIKit

struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL

    private let adaptiveColumns = [
        GridItem(.adaptive(minimum: 116), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                vehicleStatusField

                if !supportedModes.isEmpty {
                    modeSection
                }

                if vehicle.profile.capabilities.supportsCruise {
                    cruiseSection
                }

                if vehicle.profile.capabilities.supportsStartMode {
                    startModeSection
                }

                confirmationNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Vehicle Controls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Command not confirmed", isPresented: errorPresented) {
            Button("OK", role: .cancel) { vehicle.lastErrorMessage = nil }
        } message: {
            Text(vehicle.lastErrorMessage ?? "The scooter did not confirm the change.")
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { vehicle.lastErrorMessage != nil },
            set: { if !$0 { vehicle.lastErrorMessage = nil } }
        )
    }

    private var vehicleStatusField: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    connectionBadge
                }

                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    connectionBadge
                }
            }

            if vehicle.state.connection != .connected {
                Divider()

                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: connectionIssuePresentation.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectionIssuePresentation.title)
                            .font(.subheadline.weight(.semibold))
                        Text(connectionIssuePresentation.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    connectionAction
                }
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

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(vehicle.profile.identity.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)

            Text("Vehicle configuration")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionBadge: some View {
        Label(connectionText, systemImage: connectionSymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(connectionStyle)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .accessibilityLabel("Connection")
            .accessibilityValue(connectionText)
    }

    @ViewBuilder
    private var connectionAction: some View {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPermissionDenied:
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Image(systemName: "gear")
                        .fontWeight(.semibold)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .nembraGlassControl()
                .accessibilityLabel("Open Settings")
            case .bluetoothPoweredOff, .unsupportedConfiguration:
                EmptyView()
            case .scooterUnavailable:
                reconnectButton
            }
        } else {
            switch vehicle.state.connection {
            case .connecting, .reconnecting:
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(connectionText)
            case .disconnected:
                reconnectButton
            case .connected:
                EmptyView()
            }
        }
    }

    private var reconnectButton: some View {
        Button {
            Task { await vehicle.connect() }
        } label: {
            Group {
                if vehicle.pendingCommands.contains(.connect) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .fontWeight(.semibold)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .nembraGlassControl()
        .disabled(vehicle.pendingCommands.contains(.connect) || vehicle.isVehicleCommandPending)
        .accessibilityLabel(vehicle.pendingCommands.contains(.connect) ? "Connecting" : "Reconnect")
    }

    private var modeSection: some View {
        controlSection(
            title: "Ride Mode",
            subtitle: "Choose the vehicle's confirmed riding profile."
        ) {
            LazyVGrid(columns: adaptiveColumns, spacing: 10) {
                ForEach(supportedModes, id: \.self) { mode in
                    choiceControl(
                        title: mode.displayName,
                        subtitle: "Ride profile",
                        icon: modeIcon(mode),
                        selected: vehicle.state.rideMode == mode,
                        pending: vehicle.pendingRideMode == mode
                    ) {
                        await vehicle.setMode(mode)
                    }
                    .accessibilityIdentifier("vehicle-controls.mode.\(mode.rawValue)")
                }
            }
        }
    }

    private var cruiseSection: some View {
        controlSection(
            title: "Cruise Control",
            subtitle: "Availability and behavior remain governed by the scooter firmware."
        ) {
            LazyVGrid(columns: adaptiveColumns, spacing: 10) {
                choiceControl(
                    title: "Off",
                    subtitle: "Manual speed",
                    icon: "pause.circle",
                    selected: vehicle.state.isCruiseEnabled == false,
                    pending: vehicle.pendingCruiseValue == false
                ) {
                    await vehicle.setCruise(false)
                }
                .accessibilityIdentifier("vehicle-controls.cruise.off")

                choiceControl(
                    title: "On",
                    subtitle: "Firmware cruise",
                    icon: "speedometer",
                    selected: vehicle.state.isCruiseEnabled == true,
                    pending: vehicle.pendingCruiseValue == true
                ) {
                    await vehicle.setCruise(true)
                }
                .accessibilityIdentifier("vehicle-controls.cruise.on")
            }
        }
    }

    private var startModeSection: some View {
        controlSection(
            title: "Start Behavior",
            subtitle: "Controls when throttle may engage from a stop."
        ) {
            LazyVGrid(columns: adaptiveColumns, spacing: 10) {
                ForEach(StartMode.allCases, id: \.self) { mode in
                    choiceControl(
                        title: mode.displayName,
                        subtitle: startModeSubtitle(mode),
                        icon: startModeIcon(mode),
                        selected: vehicle.state.startMode == mode,
                        pending: vehicle.pendingStartMode == mode
                    ) {
                        await vehicle.setStartMode(mode)
                    }
                    .accessibilityIdentifier("vehicle-controls.start.\(mode.rawValue)")
                }
            }
        }
    }

    private var confirmationNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text("Nembra shows a new control state only after the scooter service confirms the command.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func controlSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
    }

    private func choiceControl(
        title: String,
        subtitle: String,
        icon: String,
        selected: Bool,
        pending: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.primary.opacity(0.11) : Color.primary.opacity(0.055))
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
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pending ? "Confirming…" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if selected && !pending {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.075) : Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(selected ? 0.10 : 0.045))
            }
        }
        .buttonStyle(.plain)
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || selected)
        .accessibilityLabel(title)
        .accessibilityValue(pending ? "Confirming" : selected ? "Selected" : "Not selected")
        .accessibilityHint("The displayed state changes only after vehicle confirmation.")
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
    }

    private var commandsAvailable: Bool {
        vehicle.state.connection == .connected
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

    private var connectionSymbol: String {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff: return "wifi.slash"
            case .bluetoothPermissionDenied: return "exclamationmark.triangle"
            case .scooterUnavailable: return "antenna.radiowaves.left.and.right"
            case .unsupportedConfiguration: return "exclamationmark.triangle.fill"
            }
        }

        switch vehicle.state.connection {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "circle.dashed"
        }
    }

    private var connectionStyle: Color {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .unsupportedConfiguration:
                return .red
            case .bluetoothPermissionDenied, .bluetoothPoweredOff, .scooterUnavailable:
                return .orange
            }
        }

        return vehicle.state.connection == .connected ? .green : .secondary
    }

    private var connectionIssuePresentation: (icon: String, title: String, message: String) {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff:
                return ("wifi.slash", "Bluetooth is off", "Turn on Bluetooth to restore vehicle controls.")
            case .bluetoothPermissionDenied:
                return ("hand.raised", "Bluetooth permission needed", "Allow Bluetooth access in Settings to connect to the scooter.")
            case .scooterUnavailable:
                return ("antenna.radiowaves.left.and.right", "Scooter not found", "Keep the scooter powered on and nearby, then try again.")
            case .unsupportedConfiguration:
                return ("exclamationmark.triangle.fill", "Controls unavailable", "This vehicle configuration is not verified for control commands.")
            }
        }

        switch vehicle.state.connection {
        case .connecting:
            return ("antenna.radiowaves.left.and.right", "Connecting", "Nembra is establishing a vehicle session.")
        case .reconnecting:
            return ("arrow.triangle.2.circlepath", "Reconnecting", "Controls stay unavailable until the scooter reconnects.")
        case .disconnected:
            return ("circle.dashed", "Vehicle offline", "Reconnect before changing vehicle settings.")
        case .connected:
            return ("checkmark.circle", "Connected", "Vehicle controls are available.")
        }
    }

    private func modeIcon(_ mode: RideMode) -> String {
        switch mode {
        case .walk: return "figure.walk"
        case .eco: return "leaf"
        case .drive: return "gauge.with.dots.needle.67percent"
        case .sport: return "bolt.fill"
        }
    }

    private func startModeIcon(_ mode: StartMode) -> String {
        switch mode {
        case .kickStart: return "figure.walk"
        case .zeroStart: return "bolt.circle"
        }
    }

    private func startModeSubtitle(_ mode: StartMode) -> String {
        switch mode {
        case .kickStart: return "Roll before throttle"
        case .zeroStart: return "Throttle from stop"
        }
    }
}
