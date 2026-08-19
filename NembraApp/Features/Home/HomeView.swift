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
    @ScaledMetric(relativeTo: .largeTitle) private var batteryNumericFontSize: CGFloat = 62
    @ScaledMetric(relativeTo: .title2) private var batteryPercentFontSize: CGFloat = 30

    @State private var pendingLockConfirmation: Bool?
    @State private var isModeSelectorPresented = false

    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    let onOpenRides: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: homeSectionSpacing) {
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
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 5)
            .padding(.bottom, 20)
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

    private var homeSectionSpacing: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? NembraMetrics.section : 10
    }

    /// Large non-accessibility categories can outgrow the measured stem
    /// corridor before `isAccessibilitySize` becomes true. Reflowing early
    /// keeps the visible copy and the scooter image physically separate.
    private var usesStackedEnergyHeroLayout: Bool {
        dynamicTypeSize.isAccessibilitySize || batteryNumericFontSize > 68
    }

    // MARK: - Vehicle identity

    private var vehicleHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    vehicleIdentity
                    vehicleControlsLink
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    vehicleIdentity
                    Spacer(minLength: 8)
                    vehicleControlsLink
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vehicleIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayVehicleName)
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .title3.weight(.bold)
                        : .headline.weight(.semibold)
                )
                .tracking(0.2)
                .foregroundStyle(NembraColor.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 7) {
                Circle()
                    .fill(connectionIndicatorColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Text(vehicleStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(NembraColor.secondaryText)
                    .lineLimit(1)
                    .fixedSize(horizontal: false, vertical: true)

                if vehicle.profile == .simulatorQA {
                    Text("SIM · QA")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(NembraColor.gold)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 20)
                        .background(NembraColor.quietSurface, in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(NembraColor.gold.opacity(0.22))
                        }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vehicle connection")
            .accessibilityValue(vehicleStatusAccessibilityValue)
            .accessibilityIdentifier("home.connection-status")
        }
    }

    private var vehicleControlsLink: some View {
        NavigationLink {
            VehicleControlsView()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.primaryText)
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 44 : 36,
                    height: dynamicTypeSize.isAccessibilitySize ? 44 : 36
                )
        }
        .buttonStyle(.glass)
        .tint(NembraColor.warmGraphite)
        .frame(minWidth: 44, minHeight: 44)
        .overlay {
            // Native glass needs a stable, high-contrast control boundary over
            // Home's near-black scene. A single cool specular rim preserves the
            // selected material character without replacing native glass.
            Circle()
                .strokeBorder(NembraColor.primaryText.opacity(0.44), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Vehicle controls")
        .accessibilityHint("Opens detailed vehicle controls and verified settings.")
    }

    private var displayVehicleName: String {
        // Simulator is an evidence source, never the product identity. Simulator
        // disclosure remains visible beside connection truth, never as identity.
        vehicle.profile == .simulatorQA
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
    }

    // MARK: - Energy hero

    private var energyHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            if batteryIsRetained {
                Label {
                    if let observedAt = vehicle.retainedBatteryObservedAt {
                        HStack(spacing: 3) {
                            Text("Last confirmed")
                            Text(observedAt, style: .relative)
                        }
                    } else {
                        Text("Last confirmed · age unavailable")
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last confirmed battery")
                .accessibilityValue(retainedBatteryFreshnessAccessibilityValue)
                .accessibilityHint("This battery value may be stale until the scooter reconnects.")
                .accessibilityIdentifier("home.battery.retained-freshness")
            }

            if isBatteryLow {
                Label("Low battery", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Low battery")
                    .accessibilityIdentifier("home.battery.low-warning")
            }

            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    cockpit.toggleBatteryPrimaryReadout()
                }
            } label: {
                Group {
                    if usesStackedEnergyHeroLayout {
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
            .accessibilityLabel(batteryInstrumentAccessibilityLabel)
            .accessibilityValue(batteryInstrumentAccessibilityValue)
            .accessibilityHint(batteryInstrumentAccessibilityHint)
            .accessibilityIdentifier("home.metric.battery")
        }
    }

    private var standardEnergyHero: some View {
        GeometryReader { proxy in
            let scooterSize = min(
                proxy.size.width * HomeHeroLayout.scooterWidthFraction,
                HomeHeroLayout.scooterMaximumSize
            )

            ZStack(alignment: .topLeading) {
                batteryReadout
                    .padding(.top, 2)

                batteryBody
                    .frame(height: HomeHeroLayout.batteryHeight)
                    .offset(y: HomeHeroLayout.batteryTop)

                HomeHeroGroundingScene(layout: .standard)
                    .equatable()
                    .frame(width: proxy.size.width, height: HomeHeroLayout.standardHeight)

                Image("ES80Side")
                    .resizable()
                    .scaledToFit()
                    .frame(width: scooterSize, height: scooterSize)
                    .shadow(color: .black.opacity(0.75), radius: 22, y: 16)
                    .shadow(color: NembraColor.gold.opacity(0.13), radius: 20, y: 18)
                    .position(
                        x: proxy.size.width * HomeHeroLayout.scooterCenterXFraction,
                        y: HomeHeroLayout.scooterCenterY
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: HomeHeroLayout.standardHeight)
        .clipped()
    }

    private var accessibilityEnergyHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            batteryReadout
            batteryBody
                .frame(height: 94)
            ZStack(alignment: .bottom) {
                HomeHeroGroundingScene(layout: .accessibility)
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                .font(.system(size: batteryNumericFontSize, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(batteryValueColor)
                .contentTransition(reduceMotion ? .identity : .numericText())

            if batteryPercent != nil {
                Text("%")
                    .font(.system(size: batteryPercentFontSize, weight: .light, design: .rounded))
                    .foregroundStyle(batteryValueColor)
            }
        }
        .frame(
            maxWidth: usesStackedEnergyHeroLayout
                ? .infinity
                : HomeHeroLayout.batteryNumericSafeWidth,
            alignment: .leading
        )
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityHidden(true)
    }

    private var batteryBody: some View {
        ZStack(alignment: .leading) {
            HomeBatteryMaterial(
                fillFraction: CGFloat(batteryFillFraction),
                isLowBattery: isBatteryLow,
                reduceTransparency: reduceTransparency
            )
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.28),
                value: batteryFillFraction
            )

            batteryRangeCopy(
                primaryColor: batteryRangePrimaryColor,
                secondaryColor: batteryRangeSecondaryColor
            )
            .accessibilityHidden(true)
        }
    }

    private func batteryRangeCopy(
        primaryColor: Color,
        secondaryColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(adaptiveRangeText)
                .font(.system(.headline, design: .rounded, weight: batteryRangePrimaryWeight))
                .tracking(0.15)
                .monospacedDigit()
                .foregroundStyle(primaryColor)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            Text(adaptiveRangeQualifier)
                .font(.caption.weight(.regular))
                .tracking(0.28)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .frame(
            maxWidth: usesStackedEnergyHeroLayout
                ? .infinity
                : HomeHeroLayout.batteryCopySafeWidth,
            alignment: .leading
        )
        .padding(.leading, 16)
        .padding(.trailing, HomeHeroLayout.batteryTerminalWidth + 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Readiness and durable Today

    private var readinessAndToday: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 7) {
            readinessRow

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    todayMetric(
                        title: "Today's trip",
                        value: todayDistanceText,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: todayDistanceAccessibilityValue,
                        identifier: "home.metric.trip"
                    )
                    Divider().overlay(NembraColor.quietLine)
                    todayMetric(
                        title: "Today's duration",
                        value: todayDurationText,
                        icon: "clock",
                        accessibilityValue: todayDurationAccessibilityValue,
                        identifier: "home.metric.duration"
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    todayMetric(
                        title: "Today's trip",
                        value: todayDistanceText,
                        icon: "point.bottomleft.forward.to.point.topright.scurvepath",
                        accessibilityValue: todayDistanceAccessibilityValue,
                        identifier: "home.metric.trip"
                    )

                    Divider()
                        .frame(height: 42)
                        .overlay(NembraColor.quietLine)

                    todayMetric(
                        title: "Today's duration",
                        value: todayDurationText,
                        icon: "clock",
                        accessibilityValue: todayDurationAccessibilityValue,
                        identifier: "home.metric.duration"
                    )
                }
            }

            if let todayEvidenceDetail {
                Text(todayEvidenceDetail)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(NembraColor.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
    }

    private var readinessRow: some View {
        Button(action: onOpenDashboard) {
            HStack(spacing: 9) {
                Image(systemName: readinessSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(readinessForeground)
                    .frame(width: 30, height: 30)
                    .background(readinessBackground, in: Circle())
                    .accessibilityHidden(true)

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(readinessVisibleText)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(NembraColor.primaryText)

                        Text(modeReadoutText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(modeReadoutColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(readinessVisibleText)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NembraColor.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text("·")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(NembraColor.secondaryText)
                        .accessibilityHidden(true)

                    Text(modeReadoutText)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(modeReadoutColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NembraColor.gold)
                    .frame(width: 28, height: 44)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel("Open Horizon Dashboard")
        .accessibilityValue(readinessAccessibilityValue)
        .accessibilityHint("Requests landscape and opens the riding cockpit.")
        .accessibilityIdentifier("home.horizon-entry")
    }

    private func todayMetric(
        title: String,
        value: String,
        icon: String,
        accessibilityValue: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 23, height: 23)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(NembraColor.primaryText)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
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
        GlassEffectContainer(spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    lightControl
                    Divider().overlay(NembraColor.quietLine)
                    lockControl
                    Divider().overlay(NembraColor.quietLine)
                    modeControl
                }
            } else {
                HStack(spacing: 0) {
                    lightControl
                    railDivider
                    lockControl
                    railDivider
                    modeControl
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 110)
        .background(
            reduceTransparency ? NembraColor.warmGraphite : NembraColor.quietSurface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(NembraColor.quietLine)
        }
    }

    private var railDivider: some View {
        Divider()
            .frame(height: 64)
            .overlay(NembraColor.quietLine)
            .accessibilityHidden(true)
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
            VStack(spacing: 6) {
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
                .frame(width: 44, height: 44)
                .modifier(HomeControlIconGlassModifier())

                VStack(spacing: 1) {
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
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(
            vehicle.state.connection != .connected ||
            vehicle.isVehicleCommandPending ||
            !available ||
            !enabled
        )
        .accessibilityLabel("\(title), \(displayedState)")
        .accessibilityValue(pending ? "Requesting confirmation" : "")
    }

    private func unavailableControl(title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.secondaryText)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.04), in: Circle())

            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NembraColor.primaryText)
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 96)
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
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(NembraColor.gold)
                .frame(width: 44, height: 44)
                .background(NembraColor.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Continue to rides")
                    .font(.subheadline.weight(.semibold))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func latestRideStateRow(
        title: String,
        detail: String,
        icon: String,
        showsProgress: Bool
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .frame(width: 44, height: 44)

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

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
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

    private var retainedBatteryFreshnessAccessibilityValue: String {
        guard let observedAt = vehicle.retainedBatteryObservedAt else {
            return "Observation time unavailable"
        }
        return "Observed \(observedAt.formatted(date: .complete, time: .shortened))"
    }

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
        if batteryIsRetained {
            if let observedAt = vehicle.retainedBatteryObservedAt {
                parts.append(
                    "last known, observed \(observedAt.formatted(date: .complete, time: .shortened))"
                )
            } else {
                parts.append("last known, observation time unavailable")
            }
        }
        return parts.joined(separator: ", ")
    }

    private var batteryValueColor: Color {
        if isBatteryLow {
            // Keep the semantic warning red bright enough for the thin rolling
            // numerals in both emphasis modes. Do not compound opacity when the
            // estimated range is primary: that made `14` fail the runtime audit.
            return Color(red: 1.00, green: 0.36, blue: 0.32)
        }

        switch (batteryIsRetained, batteryReadoutMode) {
        case (false, .percentage):
            return NembraColor.primaryText
        case (false, .estimatedRange):
            return NembraColor.primaryText.opacity(0.82)
        case (true, .percentage):
            return NembraColor.primaryText.opacity(0.86)
        case (true, .estimatedRange):
            // Retained telemetry remains visibly demoted, but never to the
            // compounded ~50% opacity that failed on the small percent glyph.
            return NembraColor.primaryText.opacity(0.74)
        }
    }

    private var batteryRangePrimaryWeight: Font.Weight {
        switch adaptiveRangeDisplay {
        case .valueMeters:
            batteryReadoutMode == .estimatedRange ? .semibold : .medium
        case .learning:
            .medium
        case .unavailable:
            .regular
        }
    }

    private var batteryRangePrimaryColor: Color {
        switch adaptiveRangeDisplay {
        case .valueMeters:
            NembraColor.primaryText.opacity(batteryIsRetained ? 0.90 : 0.96)
        case .learning:
            NembraColor.primaryText.opacity(batteryIsRetained ? 0.88 : 0.92)
        case .unavailable:
            NembraColor.primaryText.opacity(batteryIsRetained ? 0.86 : 0.90)
        }
    }

    private var batteryRangeSecondaryColor: Color {
        NembraColor.secondaryText.opacity(batteryIsRetained ? 0.90 : 0.96)
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

    /// One visible provenance line avoids repeating the same no-evidence or
    /// partial-evidence qualifier beneath both Today metrics. Each metric keeps
    /// its complete, independent accessibility value below.
    private var todayEvidenceDetail: String? {
        if !dynamicTypeSize.isAccessibilitySize,
           daily.todayAndCurrent?.today.distanceMeters.availability == .noEvidence,
           daily.todayAndCurrent?.today.durationSeconds.availability == .noEvidence {
            // The empty metric values and their independent accessibility
            // summaries already carry this truth. Omitting the duplicate
            // standard-size caption keeps the selected first fold clear of
            // native tab chrome; Accessibility sizes retain the explicit line.
            return nil
        }

        return switch (todayDistanceDetail, todayDurationDetail) {
        case (nil, nil):
            nil
        case let (distance?, duration?) where distance == duration:
            distance
        case let (distance?, duration?):
            "Trip: \(distance) · Duration: \(duration)"
        case let (distance?, nil):
            "Trip: \(distance)"
        case let (nil, duration?):
            "Duration: \(duration)"
        }
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

    private var readinessVisibleText: String {
        switch rides.status {
        case .restoring, .candidate, .active, .temporarilyDisconnected,
             .endingCandidate, .saving, .persistenceUnavailable, .failed:
            rides.statusText
        case .disabled:
            rides.statusText
        case .idle:
            vehicle.state.connection == .connected ? "Ready" : "Vehicle offline"
        }
    }

    private var readinessAccessibilityValue: String {
        [
            "Automatic ride tracking: \(rides.statusText)",
            "Vehicle: \(vehicleStatusText)",
            "Mode: \(modeAccessibilityValue)"
        ]
        .joined(separator: ". ")
    }

    private var readinessSymbol: String {
        switch rides.status {
        case .candidate, .active, .endingCandidate: "location.north.circle.fill"
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

    private var vehicleStatusAccessibilityValue: String {
        guard vehicle.profile == .simulatorQA else { return vehicleStatusText }
        return "\(vehicleStatusText). SIM, QA only, synthetic evidence"
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

/// Standard Home protects a left-side copy zone while the real ES80 silhouette
/// occupies the right-side stage. These names are intentionally semantic so a
/// later licensed hero asset can be remeasured without scattering pixel values.
private enum HomeHeroLayout {
    static let standardHeight: CGFloat = 304
    static let batteryHeight: CGFloat = 80
    static let batteryTop: CGFloat = 80
    static let batteryTerminalWidth: CGFloat = 13
    static let batteryNumericSafeWidth: CGFloat = 120
    static let batteryCopySafeWidth: CGFloat = 108
    static let scooterWidthFraction: CGFloat = 0.80
    static let scooterMaximumSize: CGFloat = 278
    static let scooterCenterXFraction: CGFloat = 0.65
    static let scooterCenterY: CGFloat = 132
}

/// A small, input-driven Canvas keeps the passive energy material out of the
/// native-glass control layer. It owns no animation timeline or display-link
/// source at idle; hosted profiling remains the authority for actual redraws.
private struct HomeBatteryMaterial: View, @MainActor Animatable {
    private static let chargeRibSpacing: CGFloat = 4

    var fillFraction: CGFloat
    let isLowBattery: Bool
    let reduceTransparency: Bool

    var animatableData: CGFloat {
        get { fillFraction }
        set { fillFraction = newValue }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            drawBattery(context: &context, size: size)
        }
        .shadow(color: .black.opacity(0.74), radius: 8, y: 7)
        .shadow(
            color: energyColor.opacity(energyGlowOpacity),
            radius: 12,
            x: -3,
            y: 3
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var energyColor: Color {
        isLowBattery ? .red : NembraColor.gold
    }

    private var energyGlowOpacity: Double {
        guard fillFraction > 0 else { return 0 }
        return reduceTransparency ? 0.07 : 0.14
    }

    private var chargeGradient: Gradient {
        if isLowBattery {
            return Gradient(stops: [
                .init(color: Color(red: 0.42, green: 0.02, blue: 0.03), location: 0),
                .init(color: Color(red: 0.78, green: 0.06, blue: 0.07), location: 0.42),
                .init(color: Color(red: 0.98, green: 0.19, blue: 0.16), location: 0.82),
                .init(color: Color(red: 1.00, green: 0.36, blue: 0.27), location: 1)
            ])
        }

        return Gradient(stops: [
            .init(color: NembraColor.deepGold.opacity(0.88), location: 0),
            .init(color: NembraColor.activeGold, location: 0.36),
            .init(color: NembraColor.gold, location: 0.74),
            .init(color: Color(red: 1.00, green: 0.82, blue: 0.38), location: 1)
        ])
    }

    private func drawBattery(context: inout GraphicsContext, size: CGSize) {
        guard size.width > HomeHeroLayout.batteryTerminalWidth + 12,
              size.height > 16 else { return }

        let terminalWidth = min(HomeHeroLayout.batteryTerminalWidth, size.width * 0.12)
        let bodyWidth = size.width - terminalWidth - 1
        let outerRect = CGRect(x: 0, y: 1, width: bodyWidth, height: size.height - 2)
        let outerRadius = min(22, outerRect.height * 0.28)
        let outerPath = RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
            .path(in: outerRect)
        let shellGradient = Gradient(stops: [
            .init(color: Color.white.opacity(reduceTransparency ? 0.28 : 0.19), location: 0),
            .init(color: Color(red: 0.19, green: 0.21, blue: 0.24), location: 0.22),
            .init(color: Color(red: 0.075, green: 0.083, blue: 0.095), location: 0.58),
            .init(color: Color.black.opacity(0.92), location: 1)
        ])
        let shellStart = CGPoint(x: outerRect.minX, y: outerRect.minY)
        let shellEnd = CGPoint(x: outerRect.maxX, y: outerRect.maxY)

        let terminalRect = CGRect(
            x: outerRect.maxX - 2,
            y: size.height * 0.31,
            width: terminalWidth + 2,
            height: size.height * 0.38
        )
        let terminalPath = RoundedRectangle(
            cornerRadius: min(5, terminalRect.height * 0.24),
            style: .continuous
        ).path(in: terminalRect)
        context.fill(
            terminalPath,
            with: .linearGradient(shellGradient, startPoint: shellStart, endPoint: shellEnd)
        )
        context.stroke(
            terminalPath,
            with: .color(Color.white.opacity(reduceTransparency ? 0.34 : 0.23)),
            style: StrokeStyle(lineWidth: 1)
        )

        context.fill(
            outerPath,
            with: .linearGradient(shellGradient, startPoint: shellStart, endPoint: shellEnd)
        )

        let innerRect = outerRect.insetBy(dx: 2.5, dy: 2.5)
        let innerPath = RoundedRectangle(
            cornerRadius: max(8, outerRadius - 2.5),
            style: .continuous
        ).path(in: innerRect)
        context.fill(
            innerPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.09), location: 0),
                    .init(color: Color(red: 0.045, green: 0.052, blue: 0.061), location: 0.22),
                    .init(color: Color(red: 0.010, green: 0.013, blue: 0.017), location: 1)
                ]),
                startPoint: CGPoint(x: innerRect.midX, y: innerRect.minY),
                endPoint: CGPoint(x: innerRect.midX, y: innerRect.maxY)
            )
        )

        let reservoirRect = innerRect.insetBy(dx: 3, dy: 3.5)
        let reservoirRadius = max(7, outerRadius - 5.5)
        let reservoirPath = RoundedRectangle(
            cornerRadius: reservoirRadius,
            style: .continuous
        ).path(in: reservoirRect)
        context.fill(
            reservoirPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0.050, green: 0.057, blue: 0.067), location: 0),
                    .init(color: Color(red: 0.016, green: 0.019, blue: 0.024), location: 0.48),
                    .init(color: Color.black.opacity(0.98), location: 1)
                ]),
                startPoint: CGPoint(x: reservoirRect.midX, y: reservoirRect.minY),
                endPoint: CGPoint(x: reservoirRect.midX, y: reservoirRect.maxY)
            )
        )

        drawCharge(
            context: &context,
            reservoirRect: reservoirRect,
            reservoirPath: reservoirPath
        )

        context.stroke(
            reservoirPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.25), location: 0),
                    .init(color: Color.white.opacity(0.07), location: 0.45),
                    .init(color: Color.black.opacity(0.65), location: 1)
                ]),
                startPoint: CGPoint(x: reservoirRect.midX, y: reservoirRect.minY),
                endPoint: CGPoint(x: reservoirRect.midX, y: reservoirRect.maxY)
            ),
            style: StrokeStyle(lineWidth: 0.8)
        )
        context.stroke(
            outerPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(reduceTransparency ? 0.55 : 0.34), location: 0),
                    .init(color: Color.white.opacity(0.11), location: 0.42),
                    .init(color: Color.black.opacity(0.72), location: 1)
                ]),
                startPoint: CGPoint(x: outerRect.midX, y: outerRect.minY),
                endPoint: CGPoint(x: outerRect.midX, y: outerRect.maxY)
            ),
            style: StrokeStyle(lineWidth: 1)
        )

        let terminalInnerRect = terminalRect.insetBy(dx: 2.25, dy: 2.25)
        let terminalInnerPath = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .path(in: terminalInnerRect)
        context.fill(
            terminalInnerPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.11, green: 0.12, blue: 0.14),
                    Color.black.opacity(0.94)
                ]),
                startPoint: CGPoint(x: terminalInnerRect.midX, y: terminalInnerRect.minY),
                endPoint: CGPoint(x: terminalInnerRect.midX, y: terminalInnerRect.maxY)
            )
        )

        // The overlapping shoulder removes the detached-terminal seam while
        // retaining the engineered outer body and proportional terminal.
        let shoulderRect = CGRect(
            x: outerRect.maxX - 3.5,
            y: terminalRect.minY + 2,
            width: 7,
            height: terminalRect.height - 4
        )
        var shoulderPath = Path()
        shoulderPath.addRect(shoulderRect)
        context.fill(
            shoulderPath,
            with: .linearGradient(shellGradient, startPoint: shellStart, endPoint: shellEnd)
        )
    }

    private func drawCharge(
        context: inout GraphicsContext,
        reservoirRect: CGRect,
        reservoirPath: Path
    ) {
        let clampedFill = min(max(fillFraction, 0), 1)
        let fillWidth = reservoirRect.width * clampedFill
        guard fillWidth > 0.5 else { return }

        let fillRect = CGRect(
            x: reservoirRect.minX,
            y: reservoirRect.minY,
            width: fillWidth,
            height: reservoirRect.height
        )
        let fillRadius = min(reservoirRect.height * 0.34, max(3, fillWidth * 0.5))
        let fillPath = RoundedRectangle(cornerRadius: fillRadius, style: .continuous)
            .path(in: fillRect)

        var chargeContext = context
        chargeContext.clip(to: reservoirPath)
        chargeContext.fill(
            fillPath,
            with: .linearGradient(
                chargeGradient,
                startPoint: CGPoint(x: fillRect.minX, y: fillRect.midY),
                endPoint: CGPoint(x: fillRect.maxX, y: fillRect.midY)
            )
        )

        chargeContext.clip(to: fillPath)
        var chargeOverlay = Path()
        chargeOverlay.addRect(fillRect)
        chargeContext.fill(
            chargeOverlay,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.24), location: 0),
                    .init(color: Color.white.opacity(0.055), location: 0.36),
                    .init(color: Color.clear, location: 0.62),
                    .init(color: Color.black.opacity(0.14), location: 1)
                ]),
                startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)
            )
        )

        // The selected instrument keeps its copy in a graphite energy well.
        // Clip the well to accepted SOC so the charge shape remains truthful,
        // while warm-white copy stays legible across both charged and empty
        // regions without changing color mid-animation.
        let fullCopyWellWidth = HomeHeroLayout.batteryCopySafeWidth + 34
        let copyWellWidth = min(fillRect.width, fullCopyWellWidth)
        if copyWellWidth > 0.5 {
            let copyWellRect = CGRect(
                x: fillRect.minX,
                y: fillRect.minY,
                width: copyWellWidth,
                height: fillRect.height
            )
            var copyWellPath = Path()
            copyWellPath.addRect(copyWellRect)
            chargeContext.fill(
                copyWellPath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color.black.opacity(0.76), location: 0),
                        .init(color: Color.black.opacity(0.68), location: 0.84),
                        .init(color: Color.black.opacity(0.08), location: 1)
                    ]),
                    startPoint: CGPoint(x: copyWellRect.minX, y: copyWellRect.midY),
                    endPoint: CGPoint(
                        x: copyWellRect.minX + fullCopyWellWidth,
                        y: copyWellRect.midY
                    )
                )
            )
        }

        var ribs = Path()
        for x in stride(
            from: fillRect.minX + 2,
            through: fillRect.maxX - 1,
            by: Self.chargeRibSpacing
        ) {
            ribs.move(to: CGPoint(x: x, y: fillRect.minY + 2.5))
            ribs.addLine(to: CGPoint(x: x, y: fillRect.maxY - 2.5))
        }
        chargeContext.stroke(
            ribs,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.22), location: 0),
                    .init(color: Color.white.opacity(0.085), location: 0.46),
                    .init(color: Color.black.opacity(0.17), location: 1)
                ]),
                startPoint: CGPoint(x: fillRect.midX, y: fillRect.minY),
                endPoint: CGPoint(x: fillRect.midX, y: fillRect.maxY)
            ),
            style: StrokeStyle(lineWidth: 0.55)
        )
    }
}

/// Static scene lighting gives the supplied cutout physical contact with the
/// floor without baking presentation pixels into the image asset. Tire, deck,
/// ambient, and energy-light layers stay passive and accessibility-hidden.
private struct HomeHeroGroundingScene: View, @MainActor Equatable {
    enum Layout: Equatable {
        case standard
        case accessibility
    }

    let layout: Layout

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let geometry = groundingGeometry(in: size)
            drawFloor(context: &context, geometry: geometry, size: size)
            drawSoftEllipse(
                context: &context,
                rect: geometry.ambientShadow,
                color: .black,
                coreOpacity: 0.76
            )
            drawSoftEllipse(
                context: &context,
                rect: geometry.goldPool,
                color: NembraColor.gold,
                coreOpacity: 0.13
            )
            drawSoftEllipse(
                context: &context,
                rect: geometry.deckShadow,
                color: .black,
                coreOpacity: 0.92
            )
            drawSoftEllipse(
                context: &context,
                rect: geometry.frontTireContact,
                color: .black,
                coreOpacity: 1
            )
            drawSoftEllipse(
                context: &context,
                rect: geometry.rearTireContact,
                color: .black,
                coreOpacity: 1
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct GroundingGeometry {
        let floorTop: CGFloat
        let ambientShadow: CGRect
        let deckShadow: CGRect
        let frontTireContact: CGRect
        let rearTireContact: CGRect
        let goldPool: CGRect
    }

    private func groundingGeometry(in size: CGSize) -> GroundingGeometry {
        switch layout {
        case .standard:
            GroundingGeometry(
                floorTop: size.height * 0.68,
                ambientShadow: CGRect(
                    x: size.width * 0.27,
                    y: size.height * 0.76,
                    width: size.width * 0.71,
                    height: size.height * 0.11
                ),
                deckShadow: CGRect(
                    x: size.width * 0.37,
                    y: size.height * 0.78,
                    width: size.width * 0.55,
                    height: size.height * 0.064
                ),
                frontTireContact: CGRect(
                    x: size.width * 0.32,
                    y: size.height * 0.805,
                    width: size.width * 0.16,
                    height: size.height * 0.036
                ),
                rearTireContact: CGRect(
                    x: size.width * 0.81,
                    y: size.height * 0.805,
                    width: size.width * 0.17,
                    height: size.height * 0.036
                ),
                goldPool: CGRect(
                    x: size.width * 0.37,
                    y: size.height * 0.765,
                    width: size.width * 0.52,
                    height: size.height * 0.15
                )
            )
        case .accessibility:
            GroundingGeometry(
                floorTop: size.height * 0.70,
                ambientShadow: CGRect(
                    x: size.width * 0.17,
                    y: size.height * 0.82,
                    width: size.width * 0.66,
                    height: size.height * 0.11
                ),
                deckShadow: CGRect(
                    x: size.width * 0.29,
                    y: size.height * 0.84,
                    width: size.width * 0.44,
                    height: size.height * 0.064
                ),
                frontTireContact: CGRect(
                    x: size.width * 0.24,
                    y: size.height * 0.87,
                    width: size.width * 0.15,
                    height: size.height * 0.038
                ),
                rearTireContact: CGRect(
                    x: size.width * 0.63,
                    y: size.height * 0.87,
                    width: size.width * 0.15,
                    height: size.height * 0.038
                ),
                goldPool: CGRect(
                    x: size.width * 0.28,
                    y: size.height * 0.82,
                    width: size.width * 0.46,
                    height: size.height * 0.15
                )
            )
        }
    }

    private func drawFloor(
        context: inout GraphicsContext,
        geometry: GroundingGeometry,
        size: CGSize
    ) {
        let floorRect = CGRect(
            x: 0,
            y: geometry.floorTop,
            width: size.width,
            height: max(0, size.height - geometry.floorTop)
        )
        var floorPath = Path()
        floorPath.addRect(floorRect)
        context.fill(
            floorPath,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.clear, location: 0),
                    .init(color: Color.white.opacity(0.018), location: 0.26),
                    .init(color: NembraColor.gold.opacity(0.024), location: 0.64),
                    .init(color: Color.clear, location: 1)
                ]),
                startPoint: CGPoint(x: floorRect.midX, y: floorRect.minY),
                endPoint: CGPoint(x: floorRect.midX, y: floorRect.maxY)
            )
        )
    }

    private func drawSoftEllipse(
        context: inout GraphicsContext,
        rect: CGRect,
        color: Color,
        coreOpacity: Double
    ) {
        var softContext = context
        softContext.addFilter(.blur(radius: max(1.5, rect.height * 0.42)))
        softContext.fill(
            Path(ellipseIn: rect),
            with: .color(color.opacity(coreOpacity * 0.52))
        )

        let contactRect = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.24)
        context.fill(
            Path(ellipseIn: contactRect),
            with: .color(color.opacity(coreOpacity * 0.18))
        )
    }
}

/// Liquid Glass belongs to the functional icon controls, not the telemetry
/// labels or the entire control rail. The parent `GlassEffectContainer` renders
/// these three shapes as one efficient group while each full button retains its
/// 44-point-or-larger hit region.
private struct HomeControlIconGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityShowBorders) private var showBorders
    @Environment(\.isEnabled) private var isEnabled

    private var shouldShowBoundary: Bool {
        reduceTransparency || showBorders
    }

    private var strongBoundaryRequested: Bool {
        showBorders || (reduceTransparency && colorSchemeContrast == .increased)
    }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(NembraColor.warmGraphite, in: Circle())
            } else if #available(iOS 26.0, *) {
                content
                    .glassEffect(.regular.interactive(isEnabled), in: .circle)
            } else {
                content
                    .background(.thinMaterial, in: Circle())
            }
        }
        .overlay {
            if shouldShowBoundary {
                Circle()
                    .strokeBorder(
                        NembraColor.primaryText.opacity(strongBoundaryRequested ? 0.42 : 0.24),
                        lineWidth: strongBoundaryRequested ? 1.5 : 1
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
