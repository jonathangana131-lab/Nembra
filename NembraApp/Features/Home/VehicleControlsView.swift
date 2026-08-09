import SwiftUI
import UIKit

struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            connectionSection

            if vehicle.profile.capabilities.supportsHeadlight {
                headlightSection
            }

            if vehicle.profile.capabilities.supportsLock {
                lockSection
            }

            if !supportedModes.isEmpty {
                modeSection
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

    private var headlightSection: some View {
        Section {
            confirmedChoiceRow(
                title: "Off",
                selected: vehicle.state.isHeadlightOn == false,
                pending: vehicle.pendingCommands.contains(.headlight)
            ) {
                await vehicle.setHeadlight(false)
            }

            confirmedChoiceRow(
                title: "On",
                selected: vehicle.state.isHeadlightOn == true,
                pending: vehicle.pendingCommands.contains(.headlight)
            ) {
                await vehicle.setHeadlight(true)
            }
        } header: {
            Text("Headlight")
        } footer: {
            Text("Nembra updates the light state only after the scooter service confirms the command.")
        }
    }

    private var lockSection: some View {
        Section {
            confirmedChoiceRow(
                title: "Unlocked",
                selected: vehicle.state.isLocked == false,
                pending: vehicle.pendingCommands.contains(.lock)
            ) {
                await vehicle.setLocked(false)
            }

            confirmedChoiceRow(
                title: "Locked",
                selected: vehicle.state.isLocked == true,
                pending: vehicle.pendingCommands.contains(.lock),
                enabled: vehicle.canLockFromCurrentSpeedEvidence
            ) {
                await vehicle.setLocked(true)
            }
        } header: {
            Text("Vehicle Lock")
        } footer: {
            if vehicle.state.isLocked == true {
                Text("Unlocking does not require Nembra to claim that the scooter is stopped. Lock state changes appear only after the scooter service confirms them.")
            } else if vehicle.simulatorQualifiedLiveSpeedKilometersPerHour == nil {
                Text("Live stopped-speed evidence is required before Nembra can lock the scooter. Unlock remains available when the scooter is connected.")
            } else if !vehicle.canLockFromCurrentSpeedEvidence {
                Text("Stop the scooter before locking it. Unlock remains available when the scooter is connected.")
            } else {
                Text("Current stopped-speed evidence is available. Nembra changes lock state only after the scooter service confirms the command.")
            }
        }
    }

    private var modeSection: some View {
        Section {
            ForEach(supportedModes, id: \.self) { mode in
                let isSelected = vehicle.state.rideMode == mode
                let isPending = vehicle.pendingRideMode == mode

                Button {
                    Task { await vehicle.setMode(mode) }
                } label: {
                    HStack {
                        Text(mode.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if isPending {
                            ProgressView().controlSize(.small)
                        } else if isSelected {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || isSelected)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityValue(choiceAccessibilityValue(selected: isSelected, pending: isPending))
            }
        } header: {
            Text("Ride Mode")
        } footer: {
            Text("Nembra changes the displayed mode only after the scooter service confirms the command.")
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
            Text("Nembra does not assign physical behavior to these options until the active scooter profile has verified evidence. Changes appear only after the scooter service confirms them.")
        }
    }

    @ViewBuilder
    private func confirmedChoiceRow(
        title: String,
        selected: Bool,
        pending: Bool,
        enabled: Bool = true,
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
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || selected || !enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(choiceAccessibilityValue(selected: selected, pending: pending))
    }

    private func choiceAccessibilityValue(selected: Bool, pending: Bool) -> String {
        if pending {
            return "Updating"
        }
        return selected ? "Selected" : "Not selected"
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

}