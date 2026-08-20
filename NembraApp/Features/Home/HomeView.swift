import SwiftUI
import UIKit

private enum HomePalette {
    static let base = Color(red: 0.025, green: 0.029, blue: 0.034)
    static let graphite = Color(red: 0.075, green: 0.083, blue: 0.095)
    static let raised = Color(red: 0.105, green: 0.114, blue: 0.128)
    static let line = Color.white.opacity(0.10)
    static let primary = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.62)
    static let gold = Color(red: 0.96, green: 0.69, blue: 0.20)
    static let deepGold = Color(red: 0.58, green: 0.34, blue: 0.06)
    static let danger = Color(red: 1.0, green: 0.31, blue: 0.27)
}

private enum HomeBatteryReadout: Equatable {
    case charge
    case learnedRange
}

/// Mainline Home built only from vehicle facts that already exist on `VehicleStore`.
///
/// The surface deliberately keeps retained/unavailable data explicit, never derives
/// learned range from battery percentage, and never turns a requested vehicle command
/// into confirmed state. It is a product projection, not an evidence authority.
struct HomeView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var pendingLockConfirmation: Bool?
    @State private var batteryReadout: HomeBatteryReadout = .charge

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                machineHeader

                if vehicle.state.connection != .connected {
                    connectionRecovery
                }

                energyHero
                rideReadiness
                controlsRail

                if !supportedModes.isEmpty {
                    modeRail
                }

                vehicleDetails
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 112 : 86)
        }
        .scrollIndicators(.hidden)
        .background(HomePalette.base.ignoresSafeArea())
        .foregroundStyle(HomePalette.primary)
        .navigationTitle("Nembra")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    VehicleControlsView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .fontWeight(.semibold)
                        .foregroundStyle(HomePalette.gold)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Vehicle controls")
            }
        }
        .toolbarBackground(HomePalette.base.opacity(0.96), for: .navigationBar)
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

    private var sectionSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 24 : 16
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

    private var machineHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    lockBadge
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    lockBadge
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.vehicle-header")
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(vehicle.profile.identity.displayName)
                .font(.title2.weight(.bold))
                .foregroundStyle(HomePalette.primary)
                .lineLimit(2)

            HStack(spacing: 7) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(vehicleStatusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(HomePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var lockBadge: some View {
        if let isLocked = vehicle.state.isLocked {
            Label(
                isLocked ? "Locked" : "Unlocked",
                systemImage: isLocked ? "lock.fill" : "lock.open"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(isLocked ? HomePalette.gold : HomePalette.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isLocked ? HomePalette.gold.opacity(0.11) : Color.white.opacity(0.05),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isLocked ? HomePalette.gold.opacity(0.24) : HomePalette.line,
                        lineWidth: 1
                    )
            }
        }
    }

    // MARK: - Energy hero

    private var energyHero: some View {
        Button {
            batteryReadout = batteryReadout == .charge ? .learnedRange : .charge
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(batteryReadout == .charge ? "ENERGY" : "LEARNED RANGE")
                            .font(.caption2.weight(.bold))
                            .tracking(2.0)
                            .foregroundStyle(HomePalette.secondary)

                        energyPrimaryValue
                    }

                    Spacer(minLength: 10)

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(HomePalette.gold)
                        .frame(width: 34, height: 34)
                        .background(HomePalette.gold.opacity(0.10), in: Circle())
                        .accessibilityHidden(true)
                }

                HomeBatterySilhouette(
                    fillFraction: batteryFillFraction,
                    isLowBattery: isBatteryLow,
                    retained: isRetainedBatteryData,
                    reduceTransparency: reduceTransparency,
                    increasedContrast: colorSchemeContrast == .increased
                )
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 78 : 68)

                HStack(alignment: .top, spacing: 12) {
                    energyTruthCopy
                    Spacer(minLength: 8)
                    Text("Tap to switch")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomePalette.secondary)
                }
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? 20 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [HomePalette.raised, HomePalette.graphite, HomePalette.base],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 30, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(
                        isBatteryLow ? HomePalette.danger.opacity(0.30) : HomePalette.gold.opacity(0.16),
                        lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(batteryReadout == .charge ? "Battery" : "Learned range")
        .accessibilityValue(energyAccessibilityValue)
        .accessibilityHint(
            batteryReadout == .charge
                ? "Double tap to show learned range availability."
                : "Double tap to show battery charge."
        )
        .accessibilityIdentifier("home.energy-hero")
    }

    @ViewBuilder
    private var energyPrimaryValue: some View {
        switch batteryReadout {
        case .charge:
            Text(batteryText)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 46 : 58, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isBatteryLow ? HomePalette.danger : HomePalette.primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        case .learnedRange:
            Text("Unavailable")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 31 : 36, weight: .semibold, design: .rounded))
                .foregroundStyle(HomePalette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var energyTruthCopy: some View {
        Group {
            switch batteryReadout {
            case .charge:
                if vehicle.state.batteryPercent == nil {
                    Text("No accepted battery value")
                } else if isRetainedBatteryData {
                    Label("Last known charge", systemImage: "clock.arrow.circlepath")
                } else {
                    Text(isBatteryLow ? "Low battery" : "Charge")
                }
            case .learnedRange:
                Text("No learned range model is wired yet")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(
            isBatteryLow && batteryReadout == .charge
                ? HomePalette.danger
                : HomePalette.secondary
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    private var batteryFillFraction: CGFloat? {
        guard let battery = vehicle.state.batteryPercent,
              (0...100).contains(battery) else { return nil }
        return CGFloat(battery) / 100
    }

    private var energyAccessibilityValue: String {
        switch batteryReadout {
        case .charge:
            guard let battery = vehicle.state.batteryPercent else {
                return "Unavailable. No accepted battery value."
            }
            let currentness = isRetainedBatteryData ? "Last known" : "Current"
            let low = isBatteryLow ? ", low battery" : ""
            return "\(currentness), \(battery) percent\(low). Battery fill represents charge."
        case .learnedRange:
            return "Unavailable. Nembra does not have a learned range model wired to this surface. Battery fill still represents charge."
        }
    }

    // MARK: - Readiness

    private var rideReadiness: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 14) {
                    readinessIdentity
                    Divider().overlay(HomePalette.line)
                    statusMetric(
                        title: "Scooter trip",
                        value: tripDistanceText,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: tripDistanceText
                    )
                    Divider().overlay(HomePalette.line)
                    statusMetric(
                        title: "Mode",
                        value: vehicle.state.rideMode?.displayName ?? "Unavailable",
                        icon: "gauge.with.dots.needle.67percent",
                        accessibilityValue: modeAccessibilityValue
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    readinessIdentity
                    Spacer(minLength: 8)
                    statusMetric(
                        title: "Trip",
                        value: tripDistanceText,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: tripDistanceText
                    )
                    statusMetric(
                        title: "Mode",
                        value: vehicle.state.rideMode?.displayName ?? "—",
                        icon: "gauge.with.dots.needle.67percent",
                        accessibilityValue: modeAccessibilityValue
                    )
                }
            }
        }
        .padding(16)
        .background(HomePalette.graphite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(HomePalette.line, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
        }
        .accessibilityIdentifier("home.readiness")
    }

    private var readinessIdentity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(readinessTitle)
                .font(.headline.weight(.bold))
                .foregroundStyle(HomePalette.primary)
            Text(readinessDetail)
                .font(.caption)
                .foregroundStyle(HomePalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ride readiness")
        .accessibilityValue("\(readinessTitle). \(readinessDetail)")
    }

    private func statusMetric(
        title: String,
        value: String,
        icon: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomePalette.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.weight(.semibold).monospacedDigit())
                .foregroundStyle(HomePalette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 116, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - Controls

    private var controlsRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("CONTROLS")

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) { actionControls }
                } else {
                    HStack(spacing: 10) { actionControls }
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
        let isInteractive = vehicle.state.connection == .connected
            && !vehicle.isVehicleCommandPending
            && available
            && enabled

        return Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(active ? HomePalette.gold.opacity(0.13) : Color.white.opacity(0.055))
                        .frame(width: 44, height: 44)
                    if pending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(HomePalette.gold)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(active ? HomePalette.gold : HomePalette.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(displayedState)
                        .font(.caption)
                        .foregroundStyle(isInteractive ? HomePalette.secondary : HomePalette.secondary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(HomePalette.graphite, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(active ? HomePalette.gold.opacity(0.18) : HomePalette.line)
        }
        .disabled(!isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(displayedState)")
        .accessibilityValue(pending ? "Requesting confirmation" : "")
    }

    private var modeRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RIDE MODE")

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    ForEach(supportedModes, id: \.self) { mode in modeChoice(mode) }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(supportedModes, id: \.self) { mode in modeChoice(mode) }
                }
            }
        }
    }

    private func modeChoice(_ mode: RideMode) -> some View {
        let isSelected = vehicle.state.rideMode == mode
        let isPending = vehicle.pendingRideMode == mode

        return Button {
            Task { await vehicle.setMode(mode) }
        } label: {
            HStack(spacing: 6) {
                Text(mode.displayName)
                    .font(.subheadline.weight(isSelected ? .bold : .semibold))
                if isPending {
                    ProgressView().controlSize(.mini).tint(HomePalette.gold)
                }
            }
            .foregroundStyle(isSelected ? Color.black : HomePalette.secondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                isSelected ? HomePalette.gold : HomePalette.graphite,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isSelected ? HomePalette.gold : HomePalette.line)
            }
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

    private var vehicleDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("VEHICLE")

            VStack(spacing: 0) {
                ForEach(vehicleDetailItems.indices, id: \.self) { index in
                    detailRow(vehicleDetailItems[index])
                    if index < vehicleDetailItems.count - 1 {
                        Divider().overlay(HomePalette.line).padding(.leading, 48)
                    }
                }

                if !vehicleDetailItems.isEmpty {
                    Divider().overlay(HomePalette.line).padding(.leading, 48)
                }

                NavigationLink {
                    VehicleControlsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 30)
                            .foregroundStyle(HomePalette.gold)
                        Text("All Vehicle Controls")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(HomePalette.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(HomePalette.secondary)
                    }
                    .frame(minHeight: 54)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14)
            .background(HomePalette.graphite, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(HomePalette.line)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(1.8)
            .foregroundStyle(HomePalette.secondary)
    }

    private func detailRow(_ item: VehicleDetailItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: item.icon)
                .frame(width: 30)
                .foregroundStyle(HomePalette.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).foregroundStyle(HomePalette.primary)
                    Text(item.value)
                        .foregroundStyle(HomePalette.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(item.title).foregroundStyle(HomePalette.primary)
                Spacer()
                Text(item.value)
                    .foregroundStyle(HomePalette.secondary)
                    .monospacedDigit()
            }
        }
        .font(.body)
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Connection recovery

    private var connectionRecovery: some View {
        let presentation = connectionRecoveryPresentation

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    connectionRecoveryText(presentation, includesIcon: true)
                    connectionRecoveryAction(presentation)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(connectionRecoveryColor)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    connectionRecoveryText(presentation, includesIcon: false)
                    Spacer(minLength: 8)
                    connectionRecoveryAction(presentation)
                }
            }
        }
        .padding(14)
        .background(connectionRecoveryColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(connectionRecoveryColor.opacity(0.22))
        }
    }

    private func connectionRecoveryText(
        _ presentation: ConnectionRecoveryPresentation,
        includesIcon: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if includesIcon {
                Image(systemName: presentation.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(connectionRecoveryColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                if presentation.action != .progress {
                    Text(presentation.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomePalette.primary)
                }
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(HomePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func connectionRecoveryAction(_ presentation: ConnectionRecoveryPresentation) -> some View {
        switch presentation.action {
        case .progress:
            ProgressView().controlSize(.small).tint(HomePalette.gold).accessibilityHidden(true)
        case .reconnect:
            Button {
                Task { await vehicle.connect() }
            } label: {
                if vehicle.pendingCommands.contains(.connect) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").fontWeight(.semibold)
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
                Image(systemName: "gear").fontWeight(.semibold)
            }
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.glass)
            .accessibilityLabel("Open Nembra settings")
        case .none:
            EmptyView()
        }
    }

    private enum ConnectionRecoveryAction: Equatable {
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
                return .init(
                    title: "Bluetooth is off",
                    message: "Turn on Bluetooth to reconnect to your scooter.",
                    icon: "antenna.radiowaves.left.and.right.slash",
                    action: .none
                )
            case .bluetoothPermissionDenied:
                return .init(
                    title: "Bluetooth access is off",
                    message: "Allow Bluetooth access in Settings to connect to your scooter.",
                    icon: "hand.raised.fill",
                    action: .settings
                )
            case .scooterUnavailable:
                return .init(
                    title: "Scooter not found",
                    message: "Make sure it’s powered on and nearby, then try again.",
                    icon: "antenna.radiowaves.left.and.right.slash",
                    action: .reconnect
                )
            case .unsupportedConfiguration:
                return .init(
                    title: "Scooter software not recognized",
                    message: "Controls stay unavailable until this hardware or firmware is verified.",
                    icon: "exclamationmark.shield.fill",
                    action: .none
                )
            }
        }

        switch vehicle.state.connection {
        case .connecting:
            return .init(
                title: "Connecting",
                message: "Establishing a confirmed vehicle connection.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .reconnecting:
            return .init(
                title: "Reconnecting",
                message: "Last confirmed values stay read-only until the scooter returns.",
                icon: "antenna.radiowaves.left.and.right",
                action: .progress
            )
        case .disconnected:
            return .init(
                title: "Scooter offline",
                message: "Controls stay read-only until the vehicle connection is confirmed.",
                icon: "bolt.horizontal.circle",
                action: .reconnect
            )
        case .connected:
            return .init(
                title: "Connected",
                message: "Vehicle connection confirmed.",
                icon: "checkmark.circle",
                action: .none
            )
        }
    }

    // MARK: - Truth helpers

    private struct VehicleDetailItem {
        let title: String
        let value: String
        let icon: String
    }

    private var vehicleDetailItems: [VehicleDetailItem] {
        var items: [VehicleDetailItem] = []
        if vehicle.profile.capabilities.supportsOdometer {
            items.append(.init(
                title: "Odometer",
                value: VehicleDisplayFormatting.distance(kilometers: vehicle.state.odometerKilometers),
                icon: "road.lanes"
            ))
        }
        if vehicle.profile.capabilities.supportsStartMode {
            items.append(.init(
                title: "Start",
                value: vehicle.state.startMode?.displayName ?? "—",
                icon: "figure.walk.motion"
            ))
        }
        if vehicle.profile.capabilities.supportsCruise {
            items.append(.init(
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

    private var isRetainedBatteryData: Bool {
        vehicle.state.dataAvailability == .retained && vehicle.state.batteryPercent != nil
    }

    private var batteryText: String {
        guard let value = vehicle.state.batteryPercent else { return "—" }
        return "\(value)%"
    }

    private var tripDistanceText: String {
        VehicleDisplayFormatting.distance(kilometers: vehicle.state.tripKilometers)
    }

    private var modeAccessibilityValue: String {
        let mode = vehicle.state.rideMode?.displayName ?? "Unavailable"
        return vehicle.state.dataAvailability == .retained ? "Last known, \(mode)" : mode
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
              !vehicle.isVehicleCommandPending else { return false }
        if requestedLocked {
            return vehicle.state.isLocked == false && vehicle.canLockFromCurrentSpeedEvidence
        }
        return vehicle.state.isLocked == true
    }

    private var isBatteryLow: Bool {
        guard let battery = vehicle.state.batteryPercent else { return false }
        return battery <= 15
    }

    private var readinessTitle: String {
        switch vehicle.state.connection {
        case .connected:
            return vehicle.state.dataAvailability == .live ? "Ready" : "Waiting for live data"
        case .connecting: return "Connecting"
        case .reconnecting: return "Recovering connection"
        case .disconnected: return "Vehicle offline"
        }
    }

    private var readinessDetail: String {
        if vehicle.state.dataAvailability == .retained {
            return "Last known values are preserved but not promoted to live."
        }
        if vehicle.state.connection == .connected && vehicle.state.dataAvailability == .live {
            return "Vehicle connection and current data are available."
        }
        return "Ride controls stay fail-closed until required current evidence is available."
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
        case .connected: return HomePalette.gold
        case .connecting, .reconnecting: return .orange
        case .disconnected: return HomePalette.secondary
        }
    }

    private var connectionRecoveryColor: Color {
        switch vehicle.state.connectionIssue {
        case .bluetoothPermissionDenied, .unsupportedConfiguration:
            return HomePalette.danger
        case .bluetoothPoweredOff, .scooterUnavailable:
            return .orange
        case .none:
            return HomePalette.gold
        }
    }
}

/// Battery fill is always charge. The surrounding Home may toggle text to learned
/// range availability, but this shape never repurposes its fill for miles.
private struct HomeBatterySilhouette: View {
    let fillFraction: CGFloat?
    let isLowBattery: Bool
    let retained: Bool
    let reduceTransparency: Bool
    let increasedContrast: Bool

    var body: some View {
        GeometryReader { proxy in
            let terminalWidth: CGFloat = 12
            let bodyWidth = max(0, proxy.size.width - terminalWidth - 2)
            let bodyRect = CGRect(x: 0, y: 0, width: bodyWidth, height: proxy.size.height)
            let inset: CGFloat = increasedContrast ? 4 : 3
            let reservoir = bodyRect.insetBy(dx: inset, dy: inset)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HomePalette.base)
                    .frame(width: bodyRect.width, height: bodyRect.height)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(increasedContrast ? 0.55 : 0.24),
                                lineWidth: increasedContrast ? 2 : 1
                            )
                    }

                if let fillFraction {
                    let clamped = min(max(fillFraction, 0), 1)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isLowBattery
                                    ? [HomePalette.danger.opacity(0.70), HomePalette.danger]
                                    : [HomePalette.deepGold, HomePalette.gold],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(retained ? 0.52 : 1)
                        .frame(
                            width: max(clamped > 0 ? 2 : 0, reservoir.width * clamped),
                            height: reservoir.height
                        )
                        .offset(x: reservoir.minX, y: reservoir.minY)
                }

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0.32 : 0.20))
                    .frame(width: terminalWidth, height: proxy.size.height * 0.38)
                    .offset(x: bodyWidth + 1)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
