import SwiftUI
import UIKit

struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            batteryRangeSection
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

    private var batteryRangeSection: some View {
        Section {
            NavigationLink {
                BatteryRangeView()
            } label: {
                Label("Battery & Range", systemImage: "battery.75percent")
            }
            .accessibilityHint("Shows authority-gated battery state and range availability.")
            .accessibilityIdentifier("vehicle-controls.battery-range")
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
                enabled: !isVehicleMoving
            ) {
                await vehicle.setLocked(true)
            }
        } header: {
            Text("Vehicle Lock")
        } footer: {
            if isVehicleMoving && vehicle.state.isLocked != true {
                Text("Stop the scooter before locking it. Unlock remains available when the scooter is connected.")
            } else {
                Text("Lock state changes appear only after the scooter service confirms them.")
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

    private var isVehicleMoving: Bool {
        (vehicle.state.speedKilometersPerHour ?? 0) >= 0.5
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Battery & Range")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("battery-range.surface")
    }

    private var batteryHero: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 14) {
            HStack(alignment: .firstTextBaseline) {
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

                Spacer(minLength: 12)

                dataBadge
            }

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
                .strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.22 : 0.07), lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryAccessibilityValue)
        .accessibilityHint("Battery values appear only when Nembra has battery-specific authority for the observation.")
        .accessibilityIdentifier("battery-range.battery")
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
            HStack {
                Label("Range", systemImage: "location.fill")
                    .font(.headline)
                Spacer()
                Text("NOT CALIBRATED")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)
            }

            Text("—")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 46 : 58, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)

            Text("Nembra will show learned remaining range here only after verified battery evidence and an accepted range model are available in the app. Until then, no estimate is manufactured.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data confidence", systemImage: "checkmark.shield")
                .font(.headline)

            evidenceRow(title: "Battery", value: batteryEvidenceText, symbol: batteryEvidenceIcon)
            Divider()
            evidenceRow(title: "Range model", value: "Waiting for verified learning evidence", symbol: "hourglass")

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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorSchemeContrast == .increased ? 0.20 : 0.06))
        }
        .accessibilityIdentifier("battery-range.evidence")
    }

    private func evidenceRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
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
