import SwiftUI
import UIKit

struct HomeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pendingLockConfirmation: Bool?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                vehicleHeader

                if vehicle.state.connection != .connected {
                    connectionRecovery
                }

                machineHero
                controlsSection

                if !supportedModes.isEmpty {
                    modeSection
                }

                vehicleSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .padding(.bottom, homeViewportBottomClearance)
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

    private var homeViewportBottomClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 100 : 76
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

    // MARK: - Machine identity

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

    // MARK: - Hero energy system

    private var machineHero: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 16) {
            HStack(alignment: .center, spacing: 10) {
                Text("ENERGY")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                dataFreshnessBadge
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    batteryInstrument
                    Divider()
                    heroContextMetrics
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    batteryInstrument
                    Spacer(minLength: 16)
                    heroContextMetrics
                        .frame(maxWidth: 142, alignment: .leading)
                }
            }

            machineReadinessStrip
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 20 : 22)
        .background(heroSurface, in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(reduceTransparency ? 0.12 : 0.07))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.machine-hero")
    }

    private var heroSurface: Color {
        reduceTransparency
            ? Color(uiColor: .secondarySystemBackground)
            : Color.primary.opacity(0.045)
    }

    private var dataFreshnessBadge: some View {
        Group {
            if vehicle.state.connection != .connected && hasRetainedSummaryData {
                Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                    .accessibilityLabel("Last known vehicle data")
                    .accessibilityHint("These values may be stale until the scooter reconnects.")
            } else if vehicle.state.connection == .connected && vehicle.state.dataAvailability == .live {
                Label("LIVE", systemImage: "wave.3.right")
                    .accessibilityLabel("Live vehicle data")
            } else {
                Label("WAITING", systemImage: "ellipsis")
                    .accessibilityLabel("Waiting for vehicle data")
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var batteryInstrument: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: batteryIcon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(batteryValueStyle)
                    .accessibilityHidden(true)

                Text(batteryText)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 44 : 54, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(batteryValueStyle)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }

            Text("BATTERY")
                .font(.caption2.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryAccessibilityValue)
        .accessibilityIdentifier("home.metric.battery")
    }

    private var heroContextMetrics: some View {
        VStack(alignment: .leading, spacing: 12) {
            heroContextMetric(
                title: "Trip",
                value: tripDistanceText,
                icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                accessibilityTitle: "Scooter Trip",
                identifier: "home.metric.trip"
            )

            heroContextMetric(
                title: "Mode",
                value: vehicle.state.rideMode?.displayName ?? "—",
                icon: "gauge.with.dots.needle.67percent",
                identifier: "home.metric.mode"
            )
        }
    }

    private func heroContextMetric(
        title: String,
        value: String,
        icon: String,
        accessibilityTitle: String? = nil,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 19)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
                    .fixedSize(horizontal: false, vertical: true)

                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private var machineReadinessStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: readinessIcon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.055), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(readinessTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(readinessDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.machine-readiness")
    }

    private var readinessIcon: String {
        if vehicle.state.connection == .connected && vehicle.state.dataAvailability == .live {
            return "checkmark"
        }
        if vehicle.state.connection == .connecting || vehicle.state.connection == .reconnecting {
            return "arrow.triangle.2.circlepath"
        }
        return "bolt.horizontal"
    }

    private var readinessTitle: String {
        if vehicle.state.connection == .connected && vehicle.state.dataAvailability == .live {
            return "Ride ready"
        }
        if vehicle.state.connection == .connected {
            return "Vehicle connected"
        }
        if vehicle.state.connection == .connecting || vehicle.state.connection == .reconnecting {
            return "Restoring vehicle link"
        }
        return "Vehicle offline"
    }

    private var readinessDetail: String {
        if vehicle.state.connection == .connected && vehicle.state.dataAvailability == .live {
            return "Live vehicle evidence is available."
        }
        if vehicle.state.connection == .connected {
            return "Waiting for fresh vehicle data before live status is shown."
        }
        if hasRetainedSummaryData {
            return "Last known values remain read-only until the scooter reconnects."
        }
        return "Connect the scooter before using vehicle controls."
    }

    // MARK: - Confirmed controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Quick Controls")

            Group {
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
            .padding(8)
            .background(
                reduceTransparency ? Color(uiColor: .secondarySystemBackground) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
            )
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

    // MARK: - Ride mode

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

    // MARK: - Vehicle detail

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
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.0)
            .foregroundStyle(.secondary)
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

    // MARK: - Connection recovery

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
                switch presentation.action {
                case .progress:
                    Text(presentation.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                default:
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                    Text(presentation.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: - Truthful display helpers

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
