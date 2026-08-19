import Foundation
import SwiftUI
import UIKit

/// Vehicle configuration for the selected graphite / warm-gold Nembra 1.0 system.
///
/// Every selected state below comes from `VehicleStore`. A tap can start a request,
/// but it never moves a selector, switch, or value ahead of scooter confirmation.
struct VehicleControlsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var pendingLockConfirmation: Bool?
    @State private var speedLimitsExpanded = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                vehicleStatusField

                if vehicle.state.connection != .connected {
                    connectionIssueField
                }

                batteryRangeSection
                modeSection
                controlRows
                confirmationNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .safeAreaPadding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(NembraColor.baseBlack.ignoresSafeArea())
        .navigationTitle("Vehicle")
        .navigationBarTitleDisplayMode(.large)
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
            Text(lockConfirmationMessage)
        }
    }

    private var tabBarClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 104 : 80
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

    // MARK: - Identity and connection truth

    private var vehicleStatusField: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(displayVehicleName)
                        .font(.title2.weight(.bold))
                        .tracking(0.2)
                        .foregroundStyle(NembraColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)
                    connectionBadge
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(displayVehicleName)
                        .font(.title2.weight(.bold))
                        .tracking(0.2)
                        .foregroundStyle(NembraColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    connectionBadge
                }
            }

            if vehicle.profile == .simulatorQA {
                HStack(spacing: 6) {
                    Text("Nembra Simulator")
                    Text("QA only · synthetic evidence")
                        .foregroundStyle(NembraColor.secondaryText)
                }
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(NembraColor.gold)
                .padding(.horizontal, 9)
                .frame(minHeight: 26)
                .background(NembraColor.quietSurface, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(NembraColor.gold.opacity(0.20))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Nembra Simulator, QA only, synthetic evidence")
            }

            if vehicle.state.dataAvailability == .retained {
                Label("Last confirmed settings shown below", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("vehicle-controls.retained-state")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("vehicle-controls.status")
    }

    private var displayVehicleName: String {
        vehicle.profile == .simulatorQA
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
    }

    private var connectionBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStyle)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(connectionText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(NembraColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connection")
        .accessibilityValue(connectionText)
    }

    private var connectionIssueField: some View {
        Group {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            connectionIssueColor.opacity(reduceTransparency ? 0.16 : 0.09),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(connectionIssueColor.opacity(0.24))
        }
        .accessibilityIdentifier("vehicle-controls.connection-recovery")
    }

    private var connectionIssueSummary: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: connectionIssuePresentation.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(connectionIssueColor)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(connectionIssuePresentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text(connectionIssuePresentation.message)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
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
                .buttonStyle(.glass)
            case .bluetoothPoweredOff, .unsupportedConfiguration:
                EmptyView()
            case .scooterUnavailable:
                reconnectButton
            }
        } else {
            switch vehicle.state.connection {
            case .connecting, .reconnecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                    Text(connectionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NembraColor.primaryText)
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
        .buttonStyle(.glass)
        .disabled(vehicle.pendingCommands.contains(.connect) || vehicle.isVehicleCommandPending)
        .accessibilityIdentifier("vehicle-controls.reconnect")
    }

    // MARK: - Battery energy core

    private var batteryRangeSection: some View {
        NavigationLink {
            BatteryRangeView()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                batteryEnergyBody

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        batteryAuthorityLabel
                        Spacer(minLength: 8)
                        Label("Battery details", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NembraColor.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        batteryAuthorityLabel
                        Label("Battery details", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NembraColor.secondaryText)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery and estimated range")
        .accessibilityValue("\(batteryAccessibilityValue). Estimated range unavailable, not calibrated.")
        .accessibilityHint("Shows battery authority and range-model evidence.")
        .accessibilityIdentifier("vehicle-controls.battery-range")
    }

    private var batteryEnergyBody: some View {
        GeometryReader { proxy in
            let terminalWidth: CGFloat = 13
            let bodyWidth = max(0, proxy.size.width - terminalWidth)
            let fillWidth = bodyWidth * batteryFillFraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(NembraColor.quietSurface)
                    .frame(width: bodyWidth)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(colorSchemeContrast == .increased ? 0.30 : 0.15),
                                lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                            )
                    }

                if let percent = vehicle.batteryDisplayPercent {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(percent <= 15 ? Color.red : NembraColor.gold)
                        .frame(width: max(percent > 0 ? 5 : 0, fillWidth))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: fillWidth)
                }

                batteryReadoutLayout
                    .frame(width: bodyWidth, height: proxy.size.height)
                    .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 22 : 25)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.11))
                    .frame(width: terminalWidth, height: proxy.size.height * 0.35)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18))
                    }
                    .offset(x: bodyWidth - 1)
            }
        }
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 270 : 178)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var batteryReadoutLayout: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 24) {
                batteryPercentReadout
                rangeReadout
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 18) {
                batteryPercentReadout
                Spacer(minLength: 8)
                rangeReadout
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var batteryPercentReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(batteryPrimaryText)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 48 : 68, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText())

            if vehicle.batteryDisplayPercent != nil {
                Text("%")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 23 : 29, weight: .light, design: .rounded))
            }
        }
        .foregroundStyle(batteryForegroundColor)
        .lineLimit(1)
    }

    private var rangeReadout: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
            Text("—")
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text("Estimated range")
                .font(.caption.weight(.medium))
            Text("Unavailable")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.7)
        }
        .foregroundStyle(rangeForegroundColor)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var batteryAuthorityLabel: some View {
        Label(batteryAuthorityText, systemImage: batteryAuthoritySymbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(batteryAuthorityColor)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Confirmed mode selector

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Ride mode")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)
                    Spacer(minLength: 8)
                    Text(modeAuthorityText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NembraColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ride mode")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)
                    Text(modeAuthorityText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NembraColor.secondaryText)
                }
            }

            if supportedModes.isEmpty {
                unavailableModeRow
            } else {
                modeSelector
            }
        }
        .accessibilityIdentifier("vehicle-controls.mode-selector")
    }

    @ViewBuilder
    private var modeSelector: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                spacing: 10
            ) {
                ForEach(supportedModes, id: \.self) { mode in
                    modeButton(mode)
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(supportedModes, id: \.self) { mode in
                    modeButton(mode)
                }
            }
            .padding(4)
            .background(
                reduceTransparency ? NembraColor.warmGraphite : NembraColor.quietSurface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(NembraColor.quietLine)
            }
        }
    }

    private func modeButton(_ mode: RideMode) -> some View {
        let selected = vehicle.state.rideMode == mode
        let pending = vehicle.pendingRideMode == mode

        return Button {
            Task { await vehicle.setMode(mode) }
        } label: {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(selected ? NembraColor.gold.opacity(0.10) : Color.clear)

                if selected {
                    Capsule()
                        .fill(NembraColor.gold)
                        .frame(width: 40, height: 3)
                }

                Group {
                    if pending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(NembraColor.gold)
                    } else {
                        Text(mode.displayName.uppercased())
                            .font(.caption.weight(selected ? .bold : .medium))
                            .tracking(1.2)
                            .foregroundStyle(selected ? NembraColor.primaryText : NembraColor.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .contentShape(Rectangle())
            .background(
                dynamicTypeSize.isAccessibilitySize ? NembraColor.quietSurface : Color.clear,
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                if dynamicTypeSize.isAccessibilitySize {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(selected ? NembraColor.gold.opacity(0.38) : NembraColor.quietLine)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending || selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(mode.displayName) ride mode")
        .accessibilityValue(controlAccessibilityValue(selected: selected, pending: pending))
        .accessibilityHint(controlAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.mode.\(mode.rawValue)")
    }

    private var unavailableModeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Ride modes unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text("No Walk, Eco, Drive, or Sport mapping has been verified for this active vehicle profile.")
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(NembraColor.quietSurface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(NembraColor.quietLine)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vehicle-controls.mode.unavailable")
    }

    // MARK: - Native quiet control rows

    private var controlRows: some View {
        VStack(spacing: 0) {
            if vehicle.profile.capabilities.supportsHeadlight {
                headlightSection
                controlDivider
            }

            if vehicle.profile.capabilities.supportsLock {
                lockSection
                controlDivider
            }

            if vehicle.profile.capabilities.supportsCruise {
                cruiseSection
                controlDivider
            }

            if !userFacingSpeedLimitControls.isEmpty {
                speedLimitSection
                controlDivider
            }

            if vehicle.profile.capabilities.supportsStartMode {
                startModeSection
                controlDivider
            }
        }
        .overlay(alignment: .top) { controlDivider }
        .accessibilityIdentifier("vehicle-controls.rows")
    }

    private var controlDivider: some View {
        Divider().overlay(NembraColor.quietLine)
    }

    private var headlightSection: some View {
        Toggle(isOn: headlightBinding) {
            controlRowLabel(
                title: "Headlight",
                subtitle: headlightSubtitle,
                symbol: vehicle.state.isHeadlightOn == true ? "lightbulb.fill" : "lightbulb",
                active: vehicle.state.isHeadlightOn == true,
                pending: vehicle.pendingCommands.contains(.headlight)
            )
        }
        .toggleStyle(.switch)
        .tint(NembraColor.gold)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .disabled(
            !commandsAvailable ||
            vehicle.isVehicleCommandPending ||
            vehicle.state.isHeadlightOn == nil
        )
        .accessibilityLabel("Headlight")
        .accessibilityValue(booleanControlAccessibilityValue(
            state: vehicle.state.isHeadlightOn,
            pending: vehicle.pendingCommands.contains(.headlight),
            trueLabel: "On",
            falseLabel: "Off"
        ))
        .accessibilityHint(controlAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.headlight")
    }

    private var headlightBinding: Binding<Bool> {
        Binding(
            get: { vehicle.state.isHeadlightOn == true },
            set: { requestedValue in
                guard vehicle.state.isHeadlightOn != requestedValue else { return }
                Task { await vehicle.setHeadlight(requestedValue) }
            }
        )
    }

    private var lockSection: some View {
        Button {
            guard let locked = vehicle.state.isLocked else { return }
            pendingLockConfirmation = !locked
        } label: {
            HStack(spacing: 14) {
                controlRowLabel(
                    title: "Vehicle lock",
                    subtitle: lockSectionSubtitle,
                    symbol: vehicle.state.isLocked == true ? "lock.fill" : "lock.open",
                    active: vehicle.state.isLocked == true,
                    pending: vehicle.pendingCommands.contains(.lock)
                )

                Spacer(minLength: 8)

                if vehicle.pendingCommands.contains(.lock) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                } else {
                    Text(lockValueText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NembraColor.secondaryText)
                        .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NembraColor.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canRequestLockChange)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vehicle lock")
        .accessibilityValue(lockAccessibilityValue)
        .accessibilityHint(lockAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.lock")
    }

    private var cruiseSection: some View {
        Toggle(isOn: cruiseBinding) {
            controlRowLabel(
                title: "Cruise control",
                subtitle: cruiseSubtitle,
                symbol: "speedometer",
                active: vehicle.state.isCruiseEnabled == true,
                pending: vehicle.pendingCommands.contains(.cruise)
            )
        }
        .toggleStyle(.switch)
        .tint(NembraColor.gold)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .disabled(
            !commandsAvailable ||
            vehicle.isVehicleCommandPending ||
            vehicle.state.isCruiseEnabled == nil
        )
        .accessibilityLabel("Cruise control")
        .accessibilityValue(booleanControlAccessibilityValue(
            state: vehicle.state.isCruiseEnabled,
            pending: vehicle.pendingCommands.contains(.cruise),
            trueLabel: "On",
            falseLabel: "Off"
        ))
        .accessibilityHint(controlAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.cruise")
    }

    private var cruiseBinding: Binding<Bool> {
        Binding(
            get: { vehicle.state.isCruiseEnabled == true },
            set: { requestedValue in
                guard vehicle.state.isCruiseEnabled != requestedValue else { return }
                Task { await vehicle.setCruise(requestedValue) }
            }
        )
    }

    private var speedLimitSection: some View {
        DisclosureGroup(isExpanded: $speedLimitsExpanded) {
            VStack(spacing: 0) {
                ForEach(userFacingSpeedLimitControls) { control in
                    speedLimitControl(control)
                    if control.id != userFacingSpeedLimitControls.last?.id {
                        Divider().overlay(NembraColor.quietLine)
                    }
                }
            }
            .padding(.leading, 58)
            .padding(.bottom, 10)
        } label: {
            controlRowLabel(
                title: "Speed limits",
                subtitle: speedLimitSummary,
                symbol: "gauge.with.needle",
                active: false,
                pending: vehicle.pendingCommands.contains(.speedLimit)
            )
        }
        .tint(NembraColor.secondaryText)
        .padding(.vertical, 12)
        .frame(minHeight: 72)
        .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: speedLimitsExpanded)
        .accessibilityIdentifier("vehicle-controls.speed-limits")
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
                        Label(speedLimitDisplay(value), systemImage: "checkmark")
                    } else {
                        Text(speedLimitDisplay(value))
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(control.mode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NembraColor.primaryText)
                    Text(speedLimitRangeDisplay(control.range))
                        .font(.caption)
                        .foregroundStyle(NembraColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if isPending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                } else {
                    Text(currentValue.map(speedLimitDisplay) ?? "Unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NembraColor.secondaryText)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(!commandsAvailable || vehicle.isVehicleCommandPending)
        .accessibilityLabel("\(control.mode.displayName) speed limit")
        .accessibilityValue(
            isPending
                ? "Confirming"
                : currentValue.map(speedLimitAccessibilityValue) ?? "Current value unavailable"
        )
        .accessibilityHint(controlAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.speed-limit.\(control.mode.rawValue)")
    }

    private var startModeSection: some View {
        Menu {
            ForEach(StartMode.allCases, id: \.self) { mode in
                Button {
                    Task { await vehicle.setStartMode(mode) }
                } label: {
                    if vehicle.state.startMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 14) {
                controlRowLabel(
                    title: "Start behavior",
                    subtitle: startModeSubtitle,
                    symbol: "figure.walk.motion",
                    active: vehicle.state.startMode != nil,
                    pending: vehicle.pendingCommands.contains(.startMode)
                )

                Spacer(minLength: 8)

                if vehicle.pendingCommands.contains(.startMode) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                } else {
                    Text(vehicle.state.startMode?.displayName ?? "Unavailable")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NembraColor.secondaryText)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .contentShape(Rectangle())
        }
        .disabled(
            !commandsAvailable ||
            vehicle.isVehicleCommandPending ||
            vehicle.state.startMode == nil
        )
        .accessibilityLabel("Start behavior")
        .accessibilityValue(startModeAccessibilityValue)
        .accessibilityHint(controlAccessibilityHint)
        .accessibilityIdentifier("vehicle-controls.start-mode")
    }

    private func controlRowLabel(
        title: String,
        subtitle: String,
        symbol: String,
        active: Bool,
        pending: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(active ? NembraColor.gold.opacity(0.12) : Color.clear)
                    .overlay {
                        Circle()
                            .strokeBorder(active ? NembraColor.gold.opacity(0.32) : NembraColor.quietLine)
                    }
                    .frame(width: 44, height: 44)

                if pending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(active ? NembraColor.gold : NembraColor.secondaryText)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(NembraColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(pending ? "Confirming with scooter…" : subtitle)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Truth presentation

    private var confirmationNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: vehicle.state.dataAvailability == .retained ? "clock.arrow.circlepath" : "checkmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 22)
                .accessibilityHidden(true)

            Text(confirmationNoteText)
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
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

    private func booleanControlAccessibilityValue(
        state: Bool?,
        pending: Bool,
        trueLabel: String,
        falseLabel: String
    ) -> String {
        if pending { return "Confirming" }
        guard let state else { return "Unavailable" }
        let value = state ? trueLabel : falseLabel
        return vehicle.state.dataAvailability == .retained ? "\(value), last confirmed" : value
    }

    private var controlAccessibilityHint: String {
        if vehicle.state.dataAvailability == .retained {
            return "Reconnect to confirm the current setting or make a change."
        }
        return "The displayed state changes only after vehicle confirmation."
    }

    private var commandsAvailable: Bool {
        vehicle.state.connection == .connected
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
    }

    private var modeAuthorityText: String {
        if vehicle.pendingCommands.contains(.mode) { return "Confirming with scooter" }
        if supportedModes.isEmpty { return "No verified mapping" }
        if vehicle.state.dataAvailability == .retained { return "Last confirmed by scooter" }
        if vehicle.state.rideMode == nil { return "Waiting for confirmed state" }
        return "Confirmed by scooter"
    }

    private var headlightSubtitle: String {
        if vehicle.pendingCommands.contains(.headlight) { return "Confirming with scooter" }
        guard let enabled = vehicle.state.isHeadlightOn else { return "Confirmed state unavailable" }
        let state = enabled ? "Confirmed on" : "Confirmed off"
        return vehicle.state.dataAvailability == .retained ? "Last \(state.lowercased())" : state
    }

    private var cruiseSubtitle: String {
        if vehicle.pendingCommands.contains(.cruise) { return "Confirming with scooter" }
        guard let enabled = vehicle.state.isCruiseEnabled else { return "Confirmed state unavailable" }
        let state = enabled ? "Confirmed on" : "Confirmed off"
        return vehicle.state.dataAvailability == .retained ? "Last \(state.lowercased())" : state
    }

    private var startModeSubtitle: String {
        if vehicle.state.startMode == nil { return "Confirmed state unavailable" }
        return vehicle.state.dataAvailability == .retained
            ? "Last confirmed by scooter"
            : "Confirmed by scooter"
    }

    private var lockValueText: String {
        guard let locked = vehicle.state.isLocked else { return "Unavailable" }
        return locked ? "Locked" : "Unlocked"
    }

    private var lockAccessibilityValue: String {
        if vehicle.pendingCommands.contains(.lock) { return "Confirming" }
        guard let locked = vehicle.state.isLocked else { return "Unavailable" }
        let value = locked ? "Locked" : "Unlocked"
        if vehicle.state.dataAvailability == .retained { return "\(value), last confirmed" }
        if !locked, !vehicle.canLockFromCurrentSpeedEvidence {
            return "Unlocked, live stopped-speed evidence required before locking"
        }
        return value
    }

    private var lockAccessibilityHint: String {
        guard let locked = vehicle.state.isLocked else {
            return "Lock state is unavailable."
        }
        if locked { return "Asks for confirmation before requesting an unlock." }
        if !vehicle.canLockFromCurrentSpeedEvidence {
            return "Nembra requires current stopped-speed evidence before it can request a lock."
        }
        return "Asks for confirmation before requesting a lock."
    }

    private var canRequestLockChange: Bool {
        guard commandsAvailable,
              !vehicle.isVehicleCommandPending,
              let locked = vehicle.state.isLocked else { return false }
        return locked || vehicle.canLockFromCurrentSpeedEvidence
    }

    private func isLockConfirmationStillValid(_ requestedLocked: Bool) -> Bool {
        guard commandsAvailable, !vehicle.isVehicleCommandPending else { return false }
        if requestedLocked {
            return vehicle.state.isLocked == false && vehicle.canLockFromCurrentSpeedEvidence
        }
        return vehicle.state.isLocked == true
    }

    private var lockConfirmationMessage: String {
        if pendingLockConfirmation == true {
            return "Nembra requires current stopped-speed evidence and changes the lock state only after the scooter confirms the command."
        }
        return "Nembra changes the lock state only after the scooter confirms the command."
    }

    private var lockSectionSubtitle: String {
        if vehicle.pendingCommands.contains(.lock) { return "Confirming with scooter" }
        if vehicle.state.isLocked == true {
            return vehicle.state.dataAvailability == .retained
                ? "Last confirmed locked"
                : "Confirmed locked"
        }
        if vehicle.state.isLocked == nil { return "Confirmed state unavailable" }
        if vehicle.simulatorQualifiedLiveSpeedKilometersPerHour == nil {
            return "Live stopped-speed evidence required"
        }
        if !vehicle.canLockFromCurrentSpeedEvidence {
            return "Stop the scooter before locking"
        }
        return "Scooter is stationary · ready to lock"
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

    private var speedLimitSummary: String {
        userFacingSpeedLimitControls
            .map(\.mode.displayName)
            .joined(separator: ", ")
    }

    private func speedLimitDisplay(_ kilometersPerHour: Int) -> String {
        if VehicleDisplayFormatting.usesMetric {
            return "\(kilometersPerHour) km/h"
        }
        let milesPerHour = Double(kilometersPerHour) * 0.621_371
        return String(
            format: "%.1f mph (%d km/h)",
            locale: Locale.current,
            milesPerHour,
            kilometersPerHour
        )
    }

    private func speedLimitRangeDisplay(_ range: SpeedLimitRange) -> String {
        if VehicleDisplayFormatting.usesMetric {
            return "\(range.minimumKilometersPerHour)–\(range.maximumKilometersPerHour) km/h verified"
        }
        let lower = Double(range.minimumKilometersPerHour) * 0.621_371
        let upper = Double(range.maximumKilometersPerHour) * 0.621_371
        return String(
            format: "%.1f–%.1f mph (%d–%d km/h) verified",
            locale: Locale.current,
            lower,
            upper,
            range.minimumKilometersPerHour,
            range.maximumKilometersPerHour
        )
    }

    private func speedLimitAccessibilityValue(_ kilometersPerHour: Int) -> String {
        if VehicleDisplayFormatting.usesMetric {
            return "\(kilometersPerHour) kilometers per hour"
        }
        let milesPerHour = Double(kilometersPerHour) * 0.621_371
        return String(
            format: "%.1f miles per hour, exact command %d kilometers per hour",
            locale: Locale.current,
            milesPerHour,
            kilometersPerHour
        )
    }

    private var startModeAccessibilityValue: String {
        if vehicle.pendingCommands.contains(.startMode) { return "Confirming" }
        guard let mode = vehicle.state.startMode else { return "Unavailable" }
        return vehicle.state.dataAvailability == .retained
            ? "\(mode.displayName), last confirmed"
            : mode.displayName
    }

    private var batteryPrimaryText: String {
        vehicle.batteryDisplayPercent.map(String.init) ?? "—"
    }

    private var batteryFillFraction: CGFloat {
        CGFloat(vehicle.batteryDisplayPercent ?? 0) / 100
    }

    private var batteryForegroundColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return NembraColor.secondaryText }
        if percent <= 15 { return NembraColor.primaryText }
        return percent >= 32 ? Color.black.opacity(0.78) : NembraColor.primaryText
    }

    private var rangeForegroundColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return NembraColor.secondaryText }
        if percent <= 15 { return NembraColor.primaryText }
        return percent >= 64 ? Color.black.opacity(0.72) : NembraColor.secondaryText
    }

    private var batteryAuthorityText: String {
        switch vehicle.batteryDataAvailability {
        case .live: return "Current battery evidence accepted"
        case .retained:
            if let observedAt = vehicle.retainedBatteryObservedAt {
                return "Last known · \(observedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Last known battery evidence"
        case .unavailable: return "Battery evidence unavailable"
        }
    }

    private var batteryAuthoritySymbol: String {
        switch vehicle.batteryDataAvailability {
        case .live: return "checkmark.shield.fill"
        case .retained: return "clock.arrow.circlepath"
        case .unavailable: return "questionmark.circle"
        }
    }

    private var batteryAuthorityColor: Color {
        switch vehicle.batteryDataAvailability {
        case .live: return .green
        case .retained: return NembraColor.gold
        case .unavailable: return NembraColor.secondaryText
        }
    }

    private var batteryAccessibilityValue: String {
        guard let percent = vehicle.batteryDisplayPercent else { return "Battery unavailable" }
        switch vehicle.batteryDataAvailability {
        case .live: return "Battery \(percent) percent, current accepted evidence"
        case .retained: return "Battery \(percent) percent, last known"
        case .unavailable: return "Battery unavailable"
        }
    }

    private var connectionText: String {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff: return "Bluetooth off"
            case .bluetoothPermissionDenied: return "Permission needed"
            case .scooterUnavailable: return "Not found"
            case .unsupportedConfiguration: return "Unsupported configuration"
            }
        }

        switch vehicle.state.connection {
        case .connected:
            return vehicle.state.dataAvailability == .live ? "Connected" : "Connected · waiting for data"
        case .connecting: return "Connecting"
        case .reconnecting:
            return vehicle.state.dataAvailability == .retained ? "Reconnecting · last known" : "Reconnecting"
        case .disconnected:
            return vehicle.state.dataAvailability == .retained ? "Offline · last known" : "Offline"
        }
    }

    private var connectionStyle: Color {
        switch vehicle.state.connection {
        case .connected: return .green
        case .connecting, .reconnecting: return NembraColor.gold
        case .disconnected: return NembraColor.secondaryText
        }
    }

    private var connectionIssueColor: Color {
        switch vehicle.state.connectionIssue {
        case .bluetoothPermissionDenied, .unsupportedConfiguration: return .red
        case .bluetoothPoweredOff, .scooterUnavailable: return .orange
        case .none: return NembraColor.gold
        }
    }

    private var connectionIssuePresentation: (icon: String, title: String, message: String) {
        if let issue = vehicle.state.connectionIssue {
            switch issue {
            case .bluetoothPoweredOff:
                return ("antenna.radiowaves.left.and.right.slash", "Bluetooth is off", "Turn on Bluetooth to restore vehicle controls.")
            case .bluetoothPermissionDenied:
                return ("hand.raised.fill", "Bluetooth permission needed", "Allow Bluetooth access in Settings to connect to the scooter.")
            case .scooterUnavailable:
                return ("antenna.radiowaves.left.and.right.slash", "Scooter not found", "Keep the scooter powered on and nearby, then try again.")
            case .unsupportedConfiguration:
                return ("exclamationmark.shield.fill", "Controls unavailable", "This vehicle configuration is not verified for control commands.")
            }
        }

        switch vehicle.state.connection {
        case .connecting:
            return ("antenna.radiowaves.left.and.right", "Connecting", "Nembra is establishing a confirmed vehicle session.")
        case .reconnecting:
            return ("arrow.triangle.2.circlepath", "Reconnecting", "Last confirmed values remain read-only until the scooter reconnects.")
        case .disconnected:
            return ("bolt.horizontal.circle", "Vehicle offline", "Reconnect before changing vehicle settings.")
        case .connected:
            return ("checkmark.circle", "Connected", "Vehicle controls are available.")
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
            VStack(alignment: .leading, spacing: NembraMetrics.section) {
                batteryHero
                rangeSection
                evidenceSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
            .safeAreaPadding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .background(NembraColor.baseBlack.ignoresSafeArea())
        .navigationTitle("Battery & Range")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("battery-range.surface")
    }

    private var tabBarClearance: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 104 : 80
    }

    private var batteryHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Battery")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)
                    Spacer(minLength: 8)
                    dataBadge
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Battery")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)
                    dataBadge
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(batteryPrimaryText)
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 52 : 72, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if vehicle.batteryDisplayPercent != nil {
                    Text("%")
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 24 : 32, weight: .light, design: .rounded))
                }
            }
            .foregroundStyle(batteryPrimaryColor)

            batteryGauge
                .frame(height: colorSchemeContrast == .increased ? 18 : 14)

            Text(batterySupportingText)
                .font(.subheadline)
                .foregroundStyle(NembraColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            reduceTransparency ? NembraColor.warmGraphite : NembraColor.quietSurface,
            in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorSchemeContrast == .increased ? 0.26 : 0.10),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
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
                    .fill(Color.white.opacity(colorSchemeContrast == .increased ? 0.18 : 0.09))

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

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Estimated range", systemImage: "location.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(NembraColor.primaryText)

            Text("—")
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 46 : 58, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NembraColor.primaryText)

            Label("Not calibrated", systemImage: "hourglass")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.9)
                .foregroundStyle(NembraColor.gold)

            Text("Nembra will show learned remaining range only after verified battery evidence and an accepted range model are available. No manufacturer range, battery-percentage multiplication, or guessed efficiency is used.")
                .font(.subheadline)
                .foregroundStyle(NembraColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining range")
        .accessibilityValue("Unavailable, not calibrated")
        .accessibilityHint("No estimate is manufactured while range evidence is incomplete.")
        .accessibilityIdentifier("battery-range.range")
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Data confidence")
                .font(.title3.weight(.bold))
                .foregroundStyle(NembraColor.primaryText)
                .padding(.bottom, 12)

            evidenceRow(title: "Battery", value: batteryEvidenceText, symbol: batteryEvidenceIcon)
            Divider().overlay(NembraColor.quietLine)
            evidenceRow(
                title: "Range model",
                value: "Waiting for verified learning evidence",
                symbol: "hourglass"
            )

            if vehicle.batteryDataAvailability == .retained,
               let observedAt = vehicle.retainedBatteryObservedAt {
                Divider().overlay(NembraColor.quietLine)
                evidenceRow(
                    title: "Battery observed",
                    value: observedAt.formatted(date: .abbreviated, time: .shortened),
                    symbol: "clock.arrow.circlepath"
                )
            }
        }
        .overlay(alignment: .bottom) {
            Divider().overlay(NembraColor.quietLine)
        }
        .accessibilityIdentifier("battery-range.evidence")
    }

    private func evidenceRow(title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(NembraColor.gold)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(NembraColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
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
                .foregroundStyle(colorSchemeContrast == .increased ? NembraColor.primaryText : Color.green)
        case .retained:
            Label("LAST KNOWN", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundStyle(NembraColor.gold)
        case .unavailable:
            Label("WAITING", systemImage: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(NembraColor.secondaryText)
        }
    }

    private var batteryPrimaryText: String {
        vehicle.batteryDisplayPercent.map(String.init) ?? "—"
    }

    private var batteryFillFraction: CGFloat? {
        guard let percent = vehicle.batteryDisplayPercent else { return nil }
        return CGFloat(percent) / 100
    }

    private var batteryPrimaryColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return NembraColor.secondaryText }
        return percent <= 15 ? .red : NembraColor.primaryText
    }

    private var batteryFillColor: Color {
        guard let percent = vehicle.batteryDisplayPercent else { return NembraColor.secondaryText }
        if percent <= 15 { return .red }
        return NembraColor.gold
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
        guard let percent = vehicle.batteryDisplayPercent else { return "Unavailable" }
        switch vehicle.batteryDataAvailability {
        case .live: return "\(percent) percent, live"
        case .retained: return "\(percent) percent, last known"
        case .unavailable: return "Unavailable"
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
