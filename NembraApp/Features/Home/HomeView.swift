import NembraCore
import SwiftUI
import UIKit

/// Portrait Home for the selected Nembra 1.0 graphite / warm-gold direction.
///
/// This view is deliberately a projection of durable ride and vehicle truth.
/// It never owns a trip counter, promotes cached telemetry to live, or treats a
/// tapped vehicle command as confirmed state.
struct HomeView: View {
    @AppStorage(NembraPreferenceKey.haptics) private var hapticsEnabled = true
    @Environment(VehicleStore.self) private var vehicle
    @Environment(RideApplicationStore.self) private var rides
    @Environment(RideHistoryPresentationStore.self) private var history
    @Environment(DailyRidePresentationStore.self) private var daily
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var pendingLockConfirmation: Bool?
    @State private var isModeSelectorPresented = false

    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    let onOpenRides: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                vehicleHeader

                if vehicle.state.connection != .connected {
                    connectionRecovery
                }

                energyHero
                readinessAndToday
                controlsRail
                latestRideContinuation
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(NembraColor.baseBlack.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: rides.lastCompletedSessionID) {
            await history.refresh()
            await daily.refresh(currentRideSessionID: rides.activeSessionID)
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
        .confirmationDialog(
            "Ride mode",
            isPresented: $isModeSelectorPresented,
            titleVisibility: .visible
        ) {
            ForEach(supportedModes, id: \.self) { mode in
                Button(mode.displayName) {
                    guard vehicle.state.rideMode != mode else { return }
                    Task { await vehicle.setMode(mode) }
                }
                .disabled(
                    vehicle.state.rideMode == mode ||
                    vehicle.isVehicleCommandPending ||
                    vehicle.state.connection != .connected
                )
            }

            Button("Open Horizon Dashboard") {
                onOpenDashboard()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a verified scooter mode, or open the landscape riding cockpit.")
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

    // MARK: - Vehicle identity

    private var vehicleHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    vehicleIdentity
                    vehicleControlsLink
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    vehicleControlsLink
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(displayVehicleName)
                .font(.title2.weight(.bold))
                .tracking(0.2)
                .foregroundStyle(NembraColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(vehicleStatusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if vehicle.profile == .simulatorQA {
                HStack(spacing: 6) {
                    Text("Nembra Simulator")
                        .accessibilityLabel("Nembra Simulator")
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
            }
        }
    }

    private var vehicleControlsLink: some View {
        NavigationLink {
            VehicleControlsView()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.primaryText)
                .frame(width: 50, height: 50)
        }
        .buttonStyle(.glass)
        .tint(NembraColor.warmGraphite)
        .accessibilityLabel("Vehicle controls")
        .accessibilityHint("Opens detailed vehicle controls and verified settings.")
    }

    private var displayVehicleName: String {
        // Simulator is an evidence source, never the product identity. Simulator
        // disclosure remains visible below the real target vehicle name.
        vehicle.profile == .simulatorQA
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
    }

    // MARK: - Energy hero

    private var energyHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            if batteryIsRetained {
                Label("Last known battery", systemImage: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NembraColor.secondaryText)
                    .accessibilityHint("This battery value may be stale until the scooter reconnects.")
            }

            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    cockpit.toggleBatteryPrimaryReadout()
                }
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        accessibilityEnergyHero
                    } else {
                        standardEnergyHero
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: batteryReadoutMode) { _, _ in
                hapticsEnabled
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(batteryInstrumentAccessibilityLabel)
            .accessibilityValue(batteryInstrumentAccessibilityValue)
            .accessibilityHint(batteryInstrumentAccessibilityHint)
            .accessibilityIdentifier("home.metric.battery")
        }
        .accessibilityIdentifier("home.energy-hero")
    }

    private var standardEnergyHero: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                batteryReadout
                    .padding(.top, 4)

                batteryBody
                    .frame(height: 82)
                    .padding(.trailing, 11)
                    .offset(y: 105)

                groundedShadow
                    .frame(width: proxy.size.width * 0.76, height: 36)
                    .position(x: proxy.size.width * 0.54, y: 300)

                Image("ES80Side")
                    .resizable()
                    .scaledToFit()
                    .frame(width: min(proxy.size.width * 1.08, 400), height: 246)
                    .shadow(color: .black.opacity(0.75), radius: 22, y: 16)
                    .shadow(color: NembraColor.gold.opacity(0.13), radius: 20, y: 18)
                    .position(x: proxy.size.width * 0.54, y: 218)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 338)
    }

    private var accessibilityEnergyHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            batteryReadout
            batteryBody
                .frame(height: 94)
            ZStack(alignment: .bottom) {
                groundedShadow
                    .frame(height: 36)
                Image("ES80Side")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .shadow(color: .black.opacity(0.75), radius: 20, y: 14)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 230)
        }
    }

    private var batteryReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(batteryNumericText)
                .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 54 : 72, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(
                    batteryReadoutMode == .percentage
                        ? batteryValueColor
                        : batteryValueColor.opacity(0.64)
                )
                .contentTransition(reduceMotion ? .identity : .numericText())

            if batteryPercent != nil {
                Text("%")
                    .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 27 : 34, weight: .light, design: .rounded))
                    .foregroundStyle(
                        batteryReadoutMode == .percentage
                            ? batteryValueColor
                            : batteryValueColor.opacity(0.64)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private var batteryBody: some View {
        GeometryReader { proxy in
            let terminalWidth: CGFloat = 12
            let bodyWidth = max(0, proxy.size.width - terminalWidth)
            let fillWidth = bodyWidth * batteryFillFraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .fill(Color.white.opacity(reduceTransparency ? 0.075 : 0.045))
                    .frame(width: bodyWidth)
                    .overlay {
                        RoundedRectangle(cornerRadius: 23, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }

                if batteryPercent != nil {
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(isBatteryLow ? Color.red : NembraColor.gold)
                        .frame(width: fillWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: batteryFillFraction)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(adaptiveRangeText)
                        .font(
                            .title3.weight(
                                batteryReadoutMode == .estimatedRange ? .bold : .semibold
                            )
                        )
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(adaptiveRangeQualifier)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(
                    batteryReadoutMode == .estimatedRange
                        ? rangeLabelColor
                        : rangeLabelColor.opacity(0.72)
                )
                .padding(.leading, 17)
                .padding(.trailing, 24)
                .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: terminalWidth, height: proxy.size.height * 0.47)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16))
                    }
                    .offset(x: bodyWidth - 1)
            }
        }
    }

    private var groundedShadow: some View {
        Ellipse()
            .fill(Color.black.opacity(0.86))
            .shadow(color: NembraColor.gold.opacity(0.18), radius: 22, y: -2)
            .accessibilityHidden(true)
    }

    // MARK: - Readiness and durable Today

    private var readinessAndToday: some View {
        VStack(alignment: .leading, spacing: 18) {
            readinessRow

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    todayMetric(
                        title: "Today's trip",
                        value: todayDistanceText,
                        detail: todayDistanceDetail,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: todayDistanceAccessibilityValue,
                        identifier: "home.metric.trip"
                    )
                    Divider().overlay(NembraColor.quietLine)
                    todayMetric(
                        title: "Today's duration",
                        value: todayDurationText,
                        detail: todayDurationDetail,
                        icon: "clock",
                        accessibilityValue: todayDurationAccessibilityValue,
                        identifier: "home.metric.duration"
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    todayMetric(
                        title: "Today's trip",
                        value: todayDistanceText,
                        detail: todayDistanceDetail,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: todayDistanceAccessibilityValue,
                        identifier: "home.metric.trip"
                    )

                    Divider()
                        .frame(height: 58)
                        .overlay(NembraColor.quietLine)

                    todayMetric(
                        title: "Today's duration",
                        value: todayDurationText,
                        detail: todayDurationDetail,
                        icon: "clock",
                        accessibilityValue: todayDurationAccessibilityValue,
                        identifier: "home.metric.duration"
                    )
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var readinessRow: some View {
        Button(action: onOpenDashboard) {
            HStack(spacing: 12) {
                Image(systemName: readinessSymbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(readinessForeground)
                    .frame(width: 44, height: 44)
                    .background(readinessBackground, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(readinessTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)

                    Text(modeReadoutText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(modeReadoutColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text("Dashboard")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NembraColor.secondaryText)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NembraColor.gold)
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open Horizon Dashboard")
        .accessibilityValue("\(readinessTitle), \(modeAccessibilityValue)")
        .accessibilityHint("Requests landscape and opens the riding cockpit.")
        .accessibilityIdentifier("home.horizon-entry")
    }

    private func todayMetric(
        title: String,
        value: String,
        detail: String?,
        icon: String,
        accessibilityValue: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 25, height: 25)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NembraColor.primaryText)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
                if let detail {
                    Text(detail)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(NembraColor.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Confirmed vehicle controls

    private var controlsRail: some View {
        VStack(spacing: 14) {
            GlassEffectContainer(spacing: 10) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) {
                        lightControl
                        lockControl
                        modeControl
                    }
                } else {
                    HStack(spacing: 10) {
                        lightControl
                        lockControl
                        modeControl
                    }
                }
            }

        }
        .padding(14)
        .background(
            reduceTransparency ? NembraColor.warmGraphite : NembraColor.quietSurface,
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .strokeBorder(NembraColor.quietLine)
        }
        .accessibilityIdentifier("home.controls")
    }

    @ViewBuilder
    private var lightControl: some View {
        if vehicle.profile.capabilities.supportsHeadlight {
            controlButton(
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
        } else {
            unavailableControl(title: "Light", icon: "lightbulb")
        }
    }

    @ViewBuilder
    private var lockControl: some View {
        if vehicle.profile.capabilities.supportsLock {
            controlButton(
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
        } else {
            unavailableControl(title: "Lock", icon: "lock")
        }
    }

    @ViewBuilder
    private var modeControl: some View {
        if supportedModes.isEmpty {
            unavailableControl(title: "Mode", icon: "gauge.with.dots.needle.67percent")
        } else {
            controlButton(
                title: "Mode",
                subtitle: vehicle.state.rideMode?.displayName ?? "Unknown",
                icon: modeSymbol,
                active: vehicle.state.rideMode != nil,
                pending: vehicle.pendingCommands.contains(.mode),
                available: vehicle.state.rideMode != nil,
                enabled: true
            ) {
                isModeSelectorPresented = true
            }
            .accessibilityIdentifier("home.mode.selector")
            .accessibilityHint("Opens verified ride modes and the Horizon Dashboard entry action.")
        }
    }

    private func controlButton(
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
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(active ? NembraColor.gold.opacity(0.14) : Color.white.opacity(0.055))
                        .frame(width: 44, height: 44)

                    if pending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(NembraColor.gold)
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(active ? NembraColor.gold : NembraColor.primaryText)
                    }
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NembraColor.primaryText)
                    Text(displayedState)
                        .font(.caption)
                        .foregroundStyle(NembraColor.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 100)
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

    private func unavailableControl(title: String, icon: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.04), in: Circle())

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 96 : 100)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), unavailable")
    }

    // MARK: - Durable ride-history continuation

    @ViewBuilder
    private var latestRideContinuation: some View {
        switch history.status {
        case .idle, .loading:
            latestRideStateRow(
                title: "Loading latest ride",
                detail: "Reading saved ride history",
                icon: "clock.arrow.circlepath",
                showsProgress: true
            )
            .accessibilityIdentifier("home.latest-ride.loading")
        case .ready:
            if let record = history.records.first {
                Button(action: onOpenRides) {
                    latestRideLabel(record)
                }
                .buttonStyle(.plain)
                .nembraGlassControl()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Continue to rides")
                .accessibilityValue(latestRideAccessibilityValue(record))
                .accessibilityHint("Opens saved ride history.")
                .accessibilityIdentifier("home.latest-ride.open")
            } else {
                latestRideStateRow(
                    title: "No completed rides yet",
                    detail: "Accepted rides appear here after they are safely saved",
                    icon: "clock.arrow.circlepath",
                    showsProgress: false
                )
                .accessibilityIdentifier("home.latest-ride.empty")
            }
        case .unavailable, .failed:
            latestRideStateRow(
                title: "Ride history unavailable",
                detail: history.lastErrorMessage ?? "Saved ride history could not be read safely",
                icon: "exclamationmark.triangle",
                showsProgress: false
            )
            .accessibilityIdentifier("home.latest-ride.unavailable")
        }
    }

    private func latestRideLabel(_ record: RideHistoryRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(NembraColor.gold)
                .frame(width: 48, height: 48)
                .background(NembraColor.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Continue to rides")
                    .font(.headline)
                    .foregroundStyle(NembraColor.primaryText)

                HStack(spacing: 7) {
                    Text(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(latestRideDistanceText(record))
                }
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

                if record.evidence.continuity == .recoveredCheckpoint {
                    Label("Recovered ride", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(NembraColor.gold)
                }
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(NembraColor.secondaryText)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func latestRideStateRow(
        title: String,
        detail: String,
        icon: String,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .frame(width: 48, height: 48)

                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NembraColor.gold)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NembraColor.secondaryText)
                }
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(NembraColor.quietSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(NembraColor.quietLine)
        }
        .accessibilityElement(children: .combine)
    }

    private func latestRideDistanceText(_ record: RideHistoryRecord) -> String {
        if let start = record.evidence.startingOdometerKilometers,
           let end = record.evidence.endingOdometerKilometers,
           start.isFinite,
           end.isFinite,
           end > start {
            return "Scooter \(VehicleDisplayFormatting.distance(kilometers: end - start))"
        }

        let gpsMeters = record.evidence.qualityScreenedGPSDistanceMeters
        if gpsMeters.isFinite, gpsMeters > 0 {
            return "GPS \(VehicleDisplayFormatting.distance(kilometers: gpsMeters / 1_000))"
        }

        return "Distance unavailable"
    }

    private func latestRideAccessibilityValue(_ record: RideHistoryRecord) -> String {
        var parts = [
            record.evidence.endedAtDate.formatted(date: .complete, time: .shortened),
            latestRideDistanceText(record)
        ]
        if record.evidence.continuity == .recoveredCheckpoint {
            parts.append("recovered after relaunch")
        }
        return parts.joined(separator: ", ")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(connectionRecoveryColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(connectionRecoveryColor.opacity(0.20))
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
                        .foregroundStyle(NembraColor.primaryText)
                }
                Text(presentation.message)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
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
                .tint(NembraColor.gold)
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

    // MARK: - Truthful presentation values

    private var batteryReadoutMode: NembraCore.BatteryPrimaryReadoutMode {
        cockpit.batteryPrimaryReadoutState.mode
    }

    private var adaptiveRangeDecision: NembraCore.AdaptiveRangePrimaryPresentationDecision {
        NembraCore.AdaptiveBatteryRangePrimaryPresentationPolicy()
            .resolve(liveEstimate: adaptiveRangeEstimate)
    }

    private var adaptiveRangeDisplay: NembraCore.BatteryEstimatedRangeDisplay {
        switch adaptiveRangeDecision {
        case let .valueMeters(meters): .valueMeters(meters)
        case .learning: .learning
        case .unavailable: .unavailable
        }
    }

    private var batteryPresentation: NembraCore.BatteryPrimaryReadoutPresentation {
        cockpit.batteryPrimaryReadoutState.presentation(
            for: NembraCore.BatteryPrimaryReadoutInputs(
                displaySOCPercent: vehicle.batteryDisplayPercent,
                estimatedRange: adaptiveRangeDisplay
            )
        )
    }

    private var batteryPercent: Int? { batteryPresentation.batteryFillPercent }

    private var batteryIsRetained: Bool { vehicle.batteryDataAvailability == .retained }

    private var batteryNumericText: String {
        batteryPercent.map(String.init) ?? "—"
    }

    private var batteryFillFraction: Double {
        Double(batteryPercent ?? 0) / 100
    }

    private var batteryAccessibilityValue: String {
        guard let batteryPercent else { return "Unavailable" }
        var parts = ["\(batteryPercent) percent"]
        if isBatteryLow { parts.append("low battery") }
        if batteryIsRetained { parts.append("last known") }
        return parts.joined(separator: ", ")
    }

    private var batteryValueColor: Color {
        isBatteryLow ? .red : NembraColor.primaryText
    }

    private var rangeLabelColor: Color {
        guard let batteryPercent else { return NembraColor.secondaryText }
        return batteryPercent >= 27 ? Color.black.opacity(0.74) : NembraColor.secondaryText
    }

    private var adaptiveRangeText: String {
        switch adaptiveRangeDisplay {
        case let .valueMeters(meters):
            VehicleDisplayFormatting.distance(kilometers: meters / 1_000, decimals: 1)
        case .learning:
            "Learning"
        case .unavailable:
            "Unavailable"
        }
    }

    private var adaptiveRangeQualifier: String {
        switch adaptiveRangeDecision {
        case .valueMeters: "learned range"
        case let .learning(reason), let .unavailable(reason):
            adaptiveRangeReasonQualifier(reason)
        }
    }

    private var adaptiveRangeAccessibilityValue: String {
        switch adaptiveRangeDecision {
        case let .valueMeters(meters):
            let value = VehicleDisplayFormatting.distance(kilometers: meters / 1_000, decimals: 1)
            return "\(value), learned from accepted evidence for this scooter"
        case let .learning(reason):
            return "Learning from accepted ride history, \(adaptiveRangeReasonQualifier(reason))"
        case let .unavailable(reason):
            return "Unavailable, \(adaptiveRangeReasonQualifier(reason))"
        }
    }

    private func adaptiveRangeReasonQualifier(
        _ reason: NembraCore.AdaptiveRangePrimaryPresentationReason
    ) -> String {
        switch reason {
        case .provisionalSeed: "rides needed for range"
        case .learningConfidence: "building range history"
        case .lowConfidenceRequiresQualifier: "more rides for range"
        case .noEstimate: "no learned range"
        case .retainedEstimateRequiresQualifier: "fresh range evidence"
        }
    }

    private var batteryInstrumentAccessibilityLabel: String {
        switch batteryReadoutMode {
        case .percentage: "Battery and estimated range"
        case .estimatedRange: "Estimated range and battery"
        }
    }

    private var batteryInstrumentAccessibilityValue: String {
        let emphasis = switch batteryReadoutMode {
        case .percentage: "Battery percentage emphasized"
        case .estimatedRange: "Estimated range emphasized"
        }
        return [batteryAccessibilityValue, adaptiveRangeAccessibilityValue, emphasis]
            .joined(separator: ". ")
    }

    private var batteryInstrumentAccessibilityHint: String {
        let nextValue = batteryReadoutMode == .percentage ? "estimated range" : "battery percentage"
        return "Double tap to emphasize \(nextValue). Both values remain visible. The battery fill always represents state of charge."
    }

    private var todayDistanceText: String {
        guard let meters = daily.todayAndCurrent?.today.distanceMeters.value else { return "—" }
        return VehicleDisplayFormatting.distance(kilometers: meters / 1_000)
    }

    private var todayDurationText: String {
        guard let seconds = daily.todayAndCurrent?.today.durationSeconds.value,
              seconds.isFinite,
              seconds >= 0 else { return "—" }
        let totalMinutes = Int(seconds.rounded(.down)) / 60
        if seconds > 0, totalMinutes == 0 { return "<1 min" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours) hr \(minutes) min" }
        return "\(minutes) min"
    }

    private var todayDistanceDetail: String? {
        todayMetricDetail(
            daily.todayAndCurrent?.today.distanceMeters.availability,
            unavailableText: "Distance unavailable"
        )
    }

    private var todayDurationDetail: String? {
        todayMetricDetail(
            daily.todayAndCurrent?.today.durationSeconds.availability,
            unavailableText: "Duration unavailable"
        )
    }

    private func todayMetricDetail(
        _ availability: NembraCore.DailyRideMetricAvailability?,
        unavailableText: String
    ) -> String? {
        switch availability {
        case .partial: "Partial accepted evidence"
        case .noEvidence: "No accepted rides yet"
        case .unavailable: unavailableText
        case .complete, .none: nil
        }
    }

    private var todayDistanceAccessibilityValue: String {
        metricAccessibilityValue(
            value: todayDistanceText,
            summary: daily.todayAndCurrent?.today.distanceMeters,
            unavailableLabel: "Accepted distance unavailable"
        )
    }

    private var todayDurationAccessibilityValue: String {
        metricAccessibilityValue(
            value: todayDurationText,
            summary: daily.todayAndCurrent?.today.durationSeconds,
            unavailableLabel: "Accepted duration unavailable"
        )
    }

    private func metricAccessibilityValue(
        value: String,
        summary: NembraCore.DailyRideMetricSummary?,
        unavailableLabel: String
    ) -> String {
        guard let summary else {
            switch daily.status {
            case .unavailable, .failed: return unavailableLabel
            case .idle, .loading: return "Loading accepted daily evidence"
            case .ready: return "No accepted ride evidence today"
            }
        }

        switch summary.availability {
        case .complete: return value
        case .partial: return "\(value), partial accepted evidence"
        case .noEvidence: return "No accepted ride evidence today"
        case .unavailable: return unavailableLabel
        }
    }

    private var readinessTitle: String {
        switch rides.status {
        case .candidate: "Ready when you move"
        case .active: "Recording automatically"
        case .temporarilyDisconnected: "Ride protected"
        case .endingCandidate: "Checking ride end"
        case .saving: "Saving accepted ride"
        case .restoring: "Restoring ride"
        case .persistenceUnavailable, .failed: "Ride tracking unavailable"
        case .disabled:
            vehicle.state.connection == .connected ? "Ride capture not configured" : "Ride capture unavailable"
        case .idle:
            vehicle.state.connection == .connected ? "Ready" : "Vehicle offline"
        }
    }

    private var readinessSymbol: String {
        switch rides.status {
        case .temporarilyDisconnected: "arrow.triangle.2.circlepath"
        case .persistenceUnavailable, .failed: "exclamationmark.triangle.fill"
        case .saving, .restoring: "arrow.down.doc"
        case .disabled: "pause"
        default: vehicle.state.connection == .connected ? "checkmark" : "bolt.slash"
        }
    }

    private var readinessForeground: Color {
        switch rides.status {
        case .persistenceUnavailable, .failed: .red
        case .disabled: NembraColor.secondaryText
        default: vehicle.state.connection == .connected ? Color.black : NembraColor.secondaryText
        }
    }

    private var readinessBackground: Color {
        switch rides.status {
        case .persistenceUnavailable, .failed: Color.red.opacity(0.14)
        case .disabled: Color.white.opacity(0.06)
        default: vehicle.state.connection == .connected ? NembraColor.gold : Color.white.opacity(0.06)
        }
    }

    private var modeReadoutText: String {
        guard let mode = vehicle.state.rideMode else { return "Ride mode unavailable" }
        let suffix = mode == .walk ? "" : " mode"
        return vehicle.state.dataAvailability == .retained
            ? "Last known · \(mode.displayName)\(suffix)"
            : "\(mode.displayName)\(suffix)"
    }

    private var modeAccessibilityValue: String {
        vehicle.state.rideMode?.displayName ?? "Unavailable"
    }

    private var modeReadoutColor: Color {
        vehicle.state.rideMode == nil ? NembraColor.secondaryText : NembraColor.gold
    }

    private var modeSymbol: String {
        guard let mode = vehicle.state.rideMode else { return "gauge.with.dots.needle.67percent" }
        return switch mode {
        case .walk: "figure.walk"
        case .eco: "leaf.fill"
        case .drive: "d.circle.fill"
        case .sport: "s.circle.fill"
        }
    }

    private var supportedModes: [RideMode] {
        RideMode.allCases.filter(vehicle.profile.capabilities.supportedRideModes.contains)
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
        guard let batteryPercent else { return false }
        return batteryPercent <= 15
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
        case .reconnecting:
            return vehicle.state.dataAvailability == .retained
                ? "Reconnecting · last known data"
                : "Reconnecting"
        case .disconnected:
            return vehicle.state.dataAvailability == .retained
                ? "Offline · last known data"
                : "Offline"
        }
    }

    private var connectionIndicatorColor: Color {
        switch vehicle.state.connection {
        case .connected: .green
        case .connecting, .reconnecting: NembraColor.gold
        case .disconnected: NembraColor.secondaryText
        }
    }

    private var connectionRecoveryColor: Color {
        switch vehicle.state.connectionIssue {
        case .bluetoothPermissionDenied, .unsupportedConfiguration: .red
        case .bluetoothPoweredOff, .scooterUnavailable: .orange
        case .none: NembraColor.gold
        }
    }
}
