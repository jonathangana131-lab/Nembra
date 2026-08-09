import SwiftUI
import UIKit

struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            connectionSection

            if !supportedModes.isEmpty {
                modeSection
            }

            if vehicle.profile.capabilities.supportsLock {
                lockSection
            }

            if vehicle.profile.capabilities.supportsCruise {
                cruiseSection
            }

            if vehicle.profile.capabilities.supportsStartMode {
                startModeSection
            }

        }
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

    private var connectionSection: some View {
        Section {
            LabeledContent("Scooter", value: vehicle.profile.identity.displayName)
            LabeledContent("Connection", value: connectionText)

            if vehicle.state.connection != .connected {
                switch vehicle.state.connectionIssue {
                case .bluetoothPermissionDenied:
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                case .bluetoothPoweredOff, .unsupportedConfiguration:
                    EmptyView()
                case .scooterUnavailable, .none:
                    Button {
                        Task { await vehicle.connect() }
                    } label: {
                        if vehicle.pendingCommands.contains(.connect) {
                            Label("Connecting…", systemImage: "antenna.radiowaves.left.and.right")
                        } else {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(vehicle.pendingCommands.contains(.connect) || vehicle.isVehicleCommandPending)
                }
            }
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(supportedModes, id: \.self) { mode in
                Button {
                    Task { await vehicle.setMode(mode) }
                } label: {
                    HStack {
                        Text(mode.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if vehicle.pendingRideMode == mode {
                            ProgressView().controlSize(.small)
                        } else if vehicle.state.rideMode == mode {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .disabled(!commandsAvailable || vehicle.isVehicleCommandPending)
            }
        } header: {
            Text("Ride Mode")
        } footer: {
            Text("Nembra changes the displayed mode only after the scooter service confirms the command.")
        }
    }

    private var lockSection: some View {
        Section {
            LabeledContent("State", value: lockStateText)

            Button {
                guard let locked = vehicle.state.isLocked else { return }
                Task { await vehicle.setLocked(!locked) }
            } label: {
                HStack {
                    Label(lockActionTitle, systemImage: vehicle.state.isLocked == true ? "lock.open" : "lock")
                        .foregroundStyle(.primary)
                    Spacer()
                    if vehicle.pendingCommands.contains(.lock) {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(!canChangeLockState || vehicle.isVehicleCommandPending)
            .accessibilityHint(lockAccessibilityHint)
        } header: {
            Text("Lock")
        } footer: {
            Text(lockFooterText)
        }
    }

    private var cruiseSection: some View {
        Section {
            confirmedChoiceRow(
                title: "Off",
                selected: vehicle.state.isCruiseEnabled == false,
                pending: vehicle.pendingCruiseValue == false
            ) {
                await vehicle.setCruise(false)
            }

            confirmedChoiceRow(
                title: "On",
                selected: vehicle.state.isCruiseEnabled == true,
                pending: vehicle.pendingCruiseValue == true
            ) {
                await vehicle.setCruise(true)
            }
        } header: {
            Text("Cruise Control")
        } footer: {
            Text("Cruise availability and behavior remain governed by the scooter firmware.")
        }
    }

    private var startModeSection: some View {
        Section {
            ForEach(StartMode.allCases, id: \.self) { mode in
                confirmedChoiceRow(
                    title: mode.displayName,
                    selected: vehicle.state.startMode == mode,
                    pending: vehicle.pendingStartMode == mode
                ) {
                    await vehicle.setStartMode(mode)
                }
            }
        } header: {
            Text("Start Behavior")
        } footer: {
            Text("Kick Start requires the scooter to be rolling before throttle engages. Zero Start allows throttle from a stop when supported and enabled by the vehicle.")
        }
    }

    @ViewBuilder
    private func confirmedChoiceRow(
        title: String,
        selected: Bool,
        pending: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if pending {
                    ProgressView().controlSize(.small)
                } else if selected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
            }
        }
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || selected)
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
    }

    private var commandsAvailable: Bool {
        vehicle.state.connection == .connected
    }

    private var canChangeLockState: Bool {
        guard commandsAvailable, vehicle.state.isLocked != nil else { return false }
        if vehicle.state.isLocked == true { return true }
        return vehicle.canLockFromCurrentSpeedEvidence
    }

    private var lockStateText: String {
        guard let locked = vehicle.state.isLocked else { return "Unavailable" }
        return locked ? "Locked" : "Unlocked"
    }

    private var lockActionTitle: String {
        vehicle.state.isLocked == true ? "Unlock Scooter" : "Lock Scooter"
    }

    private var lockFooterText: String {
        guard commandsAvailable else {
            return "Lock controls remain unavailable until the scooter connection is confirmed."
        }
        guard let locked = vehicle.state.isLocked else {
            return "Lock state is unavailable from the current vehicle evidence."
        }
        if locked {
            return "Unlocking does not require Nembra to claim that the scooter is stopped."
        }
        if vehicle.canLockFromCurrentSpeedEvidence {
            return "Current stopped-speed evidence is available. Nembra will change lock state only after the scooter confirms the command."
        }
        return "Live stopped-speed evidence is required before Nembra can lock the scooter."
    }

    private var lockAccessibilityHint: String {
        guard vehicle.state.isLocked != true else {
            return "Unlocks the scooter after the vehicle confirms the command."
        }
        return vehicle.canLockFromCurrentSpeedEvidence
            ? "Locks the scooter after current stopped-speed evidence and command confirmation."
            : "Unavailable until current stopped-speed evidence is available."
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

}
