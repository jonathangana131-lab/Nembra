import SwiftUI
import UIKit

struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var controlColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10)]
    }

    private var persistentNavigationViewportClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 144 : 72
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                vehicleStatusField
                batteryRangeSection

                if vehicle.profile.capabilities.supportsHeadlight {
                    headlightSection
                }

                if vehicle.profile.capabilities.supportsLock {
                    lockSection
                }

                if !supportedModes.isEmpty {
                    modeSection
                }

                if !userFacingSpeedLimitControls.isEmpty {
                    speedLimitSection
                }

                if vehicle.profile.capabilities.supportsCruise {
                    cruiseSection
                }

                if vehicle.profile.capabilities.supportsStartMode {
                    startModeSection
                }

                confirmationNote
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 40)
        }
        .padding(.bottom, persistentNavigationViewportClearance)
        .background(Color(uiColor: .systemGroupedBackground))
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
                connectionIssueField

                if vehicle.state.dataAvailability == .retained {
                    Label("Last confirmed settings shown below", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("vehicle-controls.retained-state")
                }
            }
        }
        .padding(18)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.primary.opacity(0.06))
        }
        .accessibilityIdentifier("vehicle-controls.status")
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(vehicle.profile.identity.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

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
            .background(Color.primary.opacity(0.06), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Connection")
            .accessibilityValue(connectionText)
    }

    @ViewBuilder
    private var connectionIssueField: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                connectionIssueSummary
                connectionAction
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                connectionIssueSummary
                Spacer(minLength: 8)
                connectionAction
            }
        }
    }

    private var connectionIssueSummary: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: connectionIssuePresentation.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(connectionIssuePresentation.title)
                    .font(.subheadline.weight(.semibold))
                Text(connectionIssuePresentation.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                    Label("Open Settings", systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
            case .bluetoothPoweredOff, .unsupportedConfiguration:
                EmptyView()
            case .scooterUnavailable:
                reconnectButton
            }
        } else {
            switch vehicle.state.connection {
            case .connecting, .reconnecting:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(connectionText)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
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
            HStack(spacing: 8) {
                if vehicle.pendingCommands.contains(.connect) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(vehicle.pendingCommands.contains(.connect) ? "Connecting…" : "Reconnect")
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(vehicle.pendingCommands.contains(.connect) || vehicle.isVehicleCommandPending)
        .accessibilityIdentifier("vehicle-controls.reconnect")
    }

    private var batteryRangeSection: some View {
        NavigationLink {
            BatteryRangeView()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "battery.75percent")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Battery & Range")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Authority-gated battery and learning state")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows authority-gated battery state and range availability.")
        .accessibilityIdentifier("vehicle-controls.battery-range")
    }

    private var headlightSection: some View {
        controlSection(
            title: "Headlight",
            subtitle: "Displayed state changes only after vehicle confirmation."
        ) {
            LazyVGrid(columns: controlColumns, spacing: 10) {
                choiceControl(
                    title: "Off",
                    subtitle: "Confirmed option",
                    icon: "lightbulb.slash",
                    selected: vehicle.state.isHeadlightOn == false,
                    pending: vehicle.pendingCommands.contains(.headlight)
                ) {
                    await vehicle.setHeadlight(false)
                }
                .accessibilityIdentifier("vehicle-controls.headlight.off")

                choiceControl(
                    title: "On",
                    subtitle: "Confirmed option",
                    icon: "lightbulb.fill",
                    selected: vehicle.state.isHeadlightOn == true,
                    pending: vehicle.pendingCommands.contains(.headlight)
                ) {
                    await vehicle.setHeadlight(true)
                }
                .accessibilityIdentifier("vehicle-controls.headlight.on")
            }
        }
    }

    private var lockSection: some View {
        controlSection(
            title: "Vehicle Lock",
            subtitle: lockSectionSubtitle
        ) {
            LazyVGrid(columns: controlColumns, spacing: 10) {
                choiceControl(
                    title: "Unlocked",
                    subtitle: "Confirmed option",
                    icon: "lock.open",
                    selected: vehicle.state.isLocked == false,
                    pending: vehicle.pendingCommands.contains(.lock)
                ) {
                    await vehicle.setLocked(false)
                }
                .accessibilityIdentifier("vehicle-controls.lock.unlocked")

                choiceControl(
                    title: "Locked",
                    subtitle: vehicle.canLockFromCurrentSpeedEvidence ? "Stopped-speed evidence available" : "Stopped-speed evidence required",
                    icon: "lock.fill",
                    selected: vehicle.state.isLocked == true,
                    pending: vehicle.pendingCommands.contains(.lock),
                    enabled: vehicle.canLockFromCurrentSpeedEvidence
                ) {
                    await vehicle.setLocked(true)
                }
                .accessibilityIdentifier("vehicle-controls.lock.locked")
            }
        }
    }

    private var modeSection: some View {
        controlSection(
            title: "Ride Mode",
            subtitle: "Only the scooter-confirmed mode is shown as selected."
        ) {
            LazyVGrid(columns: controlColumns, spacing: 10) {
                ForEach(supportedModes, id: \.self) { mode in
                    choiceControl(
                        title: mode.displayName,
                        subtitle: "Confirmed profile option",
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

    private var speedLimitSection: some View {
        controlSection(
            title: "Speed Limits",
            subtitle: "Only mappings and ranges verified by the active scooter profile appear here."
        ) {
            VStack(spacing: 10) {
                ForEach(userFacingSpeedLimitControls) { control in
                    speedLimitControl(control)
                }
            }
        }
    }

    private func speedLimitControl(_ control: UserFacingSpeedLimitControl) -> some View {
        let currentValue = vehicle.state.speedLimitsKilometersPerHour[control.slot]
        let isPending = vehicle.pendingSpeedLimit?.slot == control.slot

        return Menu {
            ForEach(
                control.range.minimumKilometersPerHour...control.range.maximumKilometersPerHour,
                id: \.self
            ) { value in
                Button {
                    Task {
                        await vehicle.setSpeedLimit(kilometersPerHour: value, slot: control.slot)
                    }
                } label: {
                    if currentValue == value {
                        Label("\(value) km/h", systemImage: "checkmark")
                    } else {
                        Text("\(value) km/h")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(control.mode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(control.range.minimumKilometersPerHour)–\(control.range.maximumKilometersPerHour) km/h verified range")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isPending {
                    ProgressView().controlSize(.small)
                } else {
                    Text(currentValue.map { "\($0) km/h" } ?? "Unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(0.05))
            }
        }
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending)
        .accessibilityLabel("\(control.mode.displayName) speed limit")
        .accessibilityValue(
            isPending
                ? "Updating"
                : currentValue.map { "\($0) kilometers per hour" } ?? "Current value unavailable"
        )
    }

    private var cruiseSection: some View {
        controlSection(
            title: "Cruise Control",
            subtitle: "Availability and behavior remain governed by the active scooter profile."
        ) {
            LazyVGrid(columns: controlColumns, spacing: 10) {
                choiceControl(
                    title: "Off",
                    subtitle: "Confirmed option",
                    icon: "pause.circle",
                    selected: vehicle.state.isCruiseEnabled == false,
                    pending: vehicle.pendingCruiseValue == false
                ) {
                    await vehicle.setCruise(false)
                }
                .accessibilityIdentifier("vehicle-controls.cruise.off")

                choiceControl(
                    title: "On",
                    subtitle: "Confirmed option",
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
            subtitle: "Nembra does not assign physical meaning beyond what the active profile has verified."
        ) {
            LazyVGrid(columns: controlColumns, spacing: 10) {
                ForEach(StartMode.allCases, id: \.self) { mode in
                    choiceControl(
                        title: mode.displayName,
                        subtitle: "Confirmed option",
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
            Image(systemName: vehicle.state.dataAvailability == .retained ? "clock.arrow.circlepath" : "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(confirmationNoteText)
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
        enabled: Bool = true,
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
                        ProgressView().controlSize(.small)
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
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.08) : Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.primary.opacity(selected ? 0.12 : 0.05))
            }
        }
        .buttonStyle(.plain)
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || selected || !enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
        .accessibilityValue(controlAccessibilityValue(selected: selected, pending: pending))
        .accessibilityHint(controlAccessibilityHint)
    }

    private var confirmationNoteText: String {
        if vehicle.state.dataAvailability == .retained {
            return "Selected settings are retained from the last confirmed vehicle session. Reconnect for fresh state or changes."
        }
        return "Nembra shows a new control state only after the scooter service confirms the command."
    }

    private func controlAccessibilityValue(selected: Bool, pending: Bool) -> String {
        if pending { return "Confirming" }
        guard selected else { return "Not selected" }
        return vehicle.state.dataAvailability == .retained ? "Last confirmed selection" : "Selected"
    }

    private var controlAccessibilityHint: String {
        if vehicle.state.dataAvailability == .retained {
            return "Reconnect to confirm the current setting or make a change."
        }
        return "The displayed state changes only after vehicle confirmation."
    }

    private var lockSectionSubtitle: String {
        if vehicle.state.isLocked == true {
            return "Unlocking remains available while connected; changes still require vehicle confirmation."
        }
        if vehicle.simulatorQualifiedLiveSpeedKilometersPerHour == nil {
            return "Live stopped-speed evidence is required before Nembra can lock the scooter."
        }
        if !vehicle.canLockFromCurrentSpeedEvidence {
            return "Stop the scooter before locking it."
        }
        return "Current stopped-speed evidence is available; lock state still requires vehicle confirmation."
    }

    private struct UserFacingSpeedLimitControl: Identifiable {
        let mode: RideMode
        let slot: SpeedLimitSlot
        let range: SpeedLimitRange

        var id: RideMode { mode }
    }

    private var userFacingSpeedLimitControls: [UserFacingSpeedLimitControl] {
        let capabilities = vehicle.profile.capabilities
        guard capabilities.supportsSpeedLimit,
              capabilities.hasUserFacingSpeedLimitMapping else {
            return []
        }

        return RideMode.allCases.compactMap { mode in
            guard let slot = capabilities.verifiedSpeedLimitSlotByRideMode[mode],
                  let range = capabilities.speedLimitRangesBySlot[slot] else {
                return nil
            }

            return UserFacingSpeedLimitControl(mode: mode, slot: slot, range: range)
        }
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
}

/// Product-facing Battery/Range surface.
///
/// Battery consumes only `VehicleStore`'s battery-specific authority gate. Range is
/// intentionally unavailable until the accepted learned-range model is both wired
/// into the app target and backed by verified ES80 evidence. This view never derives
/// miles from advertised range, battery percentage, voltage, trip distance, or a
/// guessed efficiency value.
private struct BatteryRangeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                batteryHero
                rangeCard
                evidenceCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .safeAreaPadding(.bottom, 36)
        }
        .padding(.bottom, persistentNavigationViewportClearance)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Battery & Range")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("battery-range.surface")
    }

    private var persistentNavigationViewportClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 144 : 72
    }

    private var batteryHero: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 14) {
            batteryHeader

            batteryGauge
                .frame(height: colorSchemeContrast == .increased ? 18 : 14)

            Text(batterySupportingText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(colorSchemeContrast == .increased ? 0.22 : 0.07),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryAccessibilityValue)
        .accessibilityHint("Battery values appear only when Nembra has battery-specific authority for the observation.")
        .accessibilityIdentifier("battery-range.battery")
    }

    @ViewBuilder
    private var batteryHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                batteryHeadingAndValue
                dataBadge
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                batteryHeadingAndValue
                Spacer(minLength: 12)
                dataBadge
            }
        }
    }

    private var batteryHeadingAndValue: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("BATTERY")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            Text(batteryPrimaryText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(batteryPrimaryColor)
                .contentTransition(reduceMotion ? .identity : .numericText())
        }
    }

    private var batteryGauge: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorSchemeContrast == .increased ? 0.18 : 0.09))

                if let fill = batteryFillFraction {
                    Capsule(style: .continuous)
                        .fill(batteryFillColor)
                        .frame(width: max(4, proxy.size.width * fill))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: fill)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var rangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            rangeHeader

            Text("—")
                .font(
                    .system(
                        size: dynamicTypeSize.isAccessibilitySize ? 46 : 58,
                        weight: .bold,
                        design: .rounded
                    )
                    .monospacedDigit()
                )
                .foregroundStyle(.primary)

            Text("Nembra will show learned remaining range here only after verified battery evidence and an accepted range model are available in the app. Until then, no estimate is manufactured.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.20 : 0.06))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining range")
        .accessibilityValue("Unavailable, not calibrated")
        .accessibilityHint("No manufacturer range, battery-percentage multiplication, or guessed efficiency is used.")
        .accessibilityIdentifier("battery-range.range")
    }

    @ViewBuilder
    private var rangeHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Label("Range", systemImage: "location.fill")
                    .font(.headline)
                Text("NOT CALIBRATED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        } else {
            HStack {
                Label("Range", systemImage: "location.fill")
                    .font(.headline)
                Spacer()
                Text("NOT CALIBRATED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data confidence", systemImage: "checkmark.shield")
                .font(.headline)

            evidenceRow(title: "Battery", value: batteryEvidenceText, symbol: batteryEvidenceIcon)
            Divider()
            evidenceRow(
                title: "Range model",
                value: "Waiting for verified learning evidence",
                symbol: "hourglass"
            )

            if vehicle.batteryDataAvailability == .retained,
               let observedAt = vehicle.retainedBatteryObservedAt {
                Divider()
                evidenceRow(
                    title: "Battery observed",
                    value: observedAt.formatted(date: .abbreviated, time: .shortened),
                    symbol: "clock.arrow.circlepath"
                )
            }
        }
        .padding(20)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.20 : 0.06))
        }
        .accessibilityIdentifier("battery-range.evidence")
    }

    private func evidenceRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 72)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    @ViewBuilder
    private var dataBadge: some View {
        switch vehicle.batteryDataAvailability {
        case .live:
            Label("LIVE", systemImage: "wave.3.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(colorSchemeContrast == .increased ? Color.primary : Color.green)
        case .retained:
            Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
        case .unavailable:
            Label("WAITING", systemImage: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private var heroBackground: Color {
        if reduceTransparency {
            return Color(uiColor: .secondarySystemGroupedBackground)
        }
        return Color.primary.opacity(colorSchemeContrast == .increased ? 0.10 : 0.055)
    }

    private var batteryPrimaryText: String {
        guard let percent = vehicle.batteryDisplayPercent else { return "—" }
        return "\(percent)%"
    }

    private var batteryFillFraction: CGFloat? {
        guard let percent = vehicle.batteryDisplayPercent else { return nil }
        return CGFloat(percent) / 100
    }

    private var batteryPrimaryColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return .secondary }
        return percent <= 15 ? .red : .primary
    }

    private var batteryFillColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return .secondary }
        if percent <= 15 { return .red }
        return colorSchemeContrast == .increased ? .primary : .green
    }

    private var batterySupportingText: String {
        switch vehicle.batteryDataAvailability {
        case .live:
            return "Current battery evidence accepted for display."
        case .retained:
            return "Last confirmed battery value. It may be stale until fresh battery evidence arrives."
        case .unavailable:
            return "No battery-specific display authority is available yet."
        }
    }

    private var batteryAccessibilityValue: String {
        guard let percent = vehicle.batteryDisplayPercent else {
            return "Unavailable"
        }
        switch vehicle.batteryDataAvailability {
        case .live:
            return "\(percent) percent, live"
        case .retained:
            return "\(percent) percent, last known"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var batteryEvidenceText: String {
        switch vehicle.batteryDataAvailability {
        case .live: return "Accepted current observation"
        case .retained: return "Accepted retained observation"
        case .unavailable: return "No display-authoritative observation"
        }
    }

    private var batteryEvidenceIcon: String {
        switch vehicle.batteryDataAvailability {
        case .live: return "checkmark.circle.fill"
        case .retained: return "clock.arrow.circlepath"
        case .unavailable: return "questionmark.circle"
        }
    }
}
