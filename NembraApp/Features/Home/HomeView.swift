import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pendingLockConfirmation: Bool?

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
            pendingLockConfirmation == true ? "Lock scooter?" : "Unlock scooter?",
            isPresented: lockConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(
                pendingLockConfirmation == true ? "Lock" : "Unlock",
                role: pendingLockConfirmation == true ? .destructive : nil
            ) {
                guard let requestedLocked = pendingLockConfirmation,
                      isLockConfirmationStillValid(requestedLocked) else { return }
                Task { await vehicle.setLocked(requestedLocked) }
            }
            .disabled(
                pendingLockConfirmation.map { !isLockConfirmationStillValid($0) } ?? true
            )
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

    private var lockConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingLockConfirmation != nil },
            set: { if !$0 { pendingLockConfirmation = nil } }
        )
    }

    private var vehicleHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    lockStatus
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 16) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    lockStatus
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var vehicleIdentity: some View {
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
    }

    @ViewBuilder
    private var lockStatus: some View {
        if let isLocked = vehicle.state.isLocked {
            Label(isLocked ? "Locked" : "Unlocked", systemImage: isLocked ? "lock.fill" : "lock.open")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isLocked ? .primary : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vehicle.state.connection != .connected && hasRetainedSummaryData {
                Label("Last known vehicle data", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHint("These values may be stale until the scooter reconnects.")
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    statusMetric(
                        title: "Battery",
                        value: batteryText,
                        icon: batteryIcon,
                        accessibilityIdentifier: "home.metric.battery",
                        accessibilityValue: batteryAccessibilityValue,
                        valueStyle: batteryValueStyle
                    )
                    accessibilityMetricDivider
                    statusMetric(
                        title: "Trip",
                        value: tripDistanceText,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityTitle: "Scooter Trip",
                        accessibilityIdentifier: "home.metric.trip"
                    )
                    accessibilityMetricDivider
                    statusMetric(
                        title: "Mode",
                        value: vehicle.state.rideMode?.displayName ?? "—",
                        icon: "gauge.with.dots.needle.67percent",
                        accessibilityIdentifier: "home.metric.mode"
                    )
                }
            } else {
                HStack(spacing: 0) {
                    statusMetric(
                        title: "Battery",
                        value: batteryText,
                        icon: batteryIcon,
                        accessibilityIdentifier: "home.metric.battery",
                        accessibilityValue: batteryAccessibilityValue,
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

    private var accessibilityMetricDivider: some View {
        Divider()
            .padding(.vertical, 12)
    }

    private func statusMetric(
        title: String,
        value: String,
        icon: String,
        accessibilityTitle: String? = nil,
        accessibilityIdentifier: String,
        accessibilityValue: String? = nil,
        valueStyle: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(title == "Battery" && isBatteryLow ? valueStyle : .secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueStyle)
                .contentTransition(.numericText())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(accessibilityValue ?? value)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Controls")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    actionControls
                }
            } else {
                HStack(spacing: 12) {
                    actionControls
                }
            }
        }
    }

    @ViewBuilder
    private var actionControls: some View {
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
                guard let locked = vehicle.state.isLocked else { return }
                pendingLockConfirmation = !locked
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
        let displayedState = available ? subtitle : "Unavailable"

        return Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(active ? Color.primary.opacity(0.10) : Color.primary.opacity(0.055))
                        .frame(width: 36, height: 36)

                    if pending {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(displayedState)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(minHeight: 58)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(displayedState)")
        .accessibilityValue(pending ? "Requesting confirmation" : "")
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Ride Mode")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(supportedModes, id: \.self) { mode in
                        modeChoice(mode)
                    }
                }
                .padding(4)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            } else {
                HStack(spacing: 4) {
                    ForEach(supportedModes, id: \.self) { mode in
                        modeChoice(mode)
                    }
                }
                .padding(4)
                .background(
                    Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
            }
        }
    }

    private func modeChoice(_ mode: RideMode) -> some View {
        let isSelected = vehicle.state.rideMode == mode
        let isPending = vehicle.pendingRideMode == mode

        return Button {
            Task { await vehicle.setMode(mode) }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                }

                HStack(spacing: 5) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)

                    if isPending {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 48 : 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(vehicle.state.connection != .connected || vehicle.isVehicleCommandPending || isSelected)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(modeChoiceAccessibilityValue(selected: isSelected, pending: isPending))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("home.mode.\(mode.displayName.lowercased())")
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

    @ViewBuilder
    private func detailRow(title: String, value: String, icon: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 26)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                    Text(value)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .font(.body)
            .padding(.vertical, 8)
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
        } else {
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
    }

    private var connectionRecovery: some View {
        let presentation = connectionRecoveryPresentation

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    connectionRecoveryText(presentation)
                    connectionRecoveryAction(presentation)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)

                    connectionRecoveryText(presentation)
                    Spacer(minLength: 8)
                    connectionRecoveryAction(presentation)
                }
            }
        }
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    @ViewBuilder
    private func connectionRecoveryText(_ presentation: ConnectionRecoveryPresentation) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: presentation.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func connectionRecoveryAction(_ presentation: ConnectionRecoveryPresentation) -> some View {
        switch presentation.action {
        case .progress:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
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
            .frame(minWidth: 44, minHeight: 44)
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
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.glass)
            .accessibilityLabel("Open Nembra settings")
        case .none:
            EmptyView()
        }
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

    private func modeChoiceAccessibilityValue(selected: Bool, pending: Bool) -> String {
        if pending { return "Requesting confirmation" }
        return selected ? "Selected" : "Not selected"
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

    private var batteryAccessibilityValue: String {
        guard let value = vehicle.state.batteryPercent else { return "Unavailable" }
        return isBatteryLow ? "\(value) percent, low battery" : "\(value) percent"
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

    private func isLockConfirmationStillValid(_ requestedLocked: Bool) -> Bool {
        guard vehicle.state.connection == .connected,
              !vehicle.isVehicleCommandPending else {
            return false
        }
        if requestedLocked {
            return vehicle.state.isLocked == false && vehicle.canLockFromCurrentSpeedEvidence
        }
        return vehicle.state.isLocked == true
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
            guard vehicle.state.dataAvailability == .live else {
                return "Connected · waiting for data"
            }
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
