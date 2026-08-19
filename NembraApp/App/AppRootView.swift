import MapKit
import NembraCore
import SwiftUI
import UIKit

enum NembraPrimaryTab: String, Hashable {
    case home
    case rides
    case vehicle
    case settings
}

@MainActor
struct AppRootView: View {
    @AppStorage(NembraPreferenceKey.appearance) private var appearanceRaw = NembraAppearancePreference.nembraDark.rawValue
    @State private var selectedTab: NembraPrimaryTab = .home
    @State private var dashboardSession = DashboardSessionStore()
    @State private var horizonCockpit = HorizonCockpitStore()
    var adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate? = nil
    var onOpenNavigation: () -> Void = {}

    var body: some View {
        ZStack {
            if dashboardSession.presentsDashboard {
                DashboardView(
                    cockpit: horizonCockpit,
                    adaptiveRangeEstimate: adaptiveRangeEstimate,
                    onHome: closeDashboard,
                    onNavigate: onOpenNavigation
                )
                .transition(.opacity)
            } else if dashboardSession.canPresentPortraitContent {
                PortraitRootView(
                    selectedTab: $selectedTab,
                    cockpit: horizonCockpit,
                    adaptiveRangeEstimate: adaptiveRangeEstimate,
                    onOpenNavigation: onOpenNavigation,
                    onOpenDashboard: openDashboard
                )
                .disabled(dashboardSession.isOpening)
                .transition(.opacity)
            } else {
                // Never lay portrait controls out in an observed landscape scene.
                // Passive rotation owns no Dashboard authority, so the only safe
                // presentation while Home restores its geometry is opaque.
                Color.black
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            DashboardWindowSceneReader { scene in
                dashboardSession.attach(windowScene: scene)
            }
            // Fill the exact root bounds so passive orientation changes relayout
            // the transparent probe and publish the owning scene's new effective
            // geometry. A fixed 1x1 probe is not guaranteed to relayout.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            if dashboardSession.isOpening || dashboardSession.isClosing {
                DashboardGeometryProgressOverlay(isClosing: dashboardSession.isClosing)
            }

            if let failure = dashboardSession.failure {
                DashboardGeometryRecoveryOverlay(
                    failure: failure,
                    message: dashboardSession.failureMessage(failure),
                    allowsKeepingStablePresentation: dashboardSession.canKeepStablePresentationAfterFailure,
                    onRetry: {
                        dashboardSession.recover(using: .retryGeometryRequest)
                    },
                    onKeepStablePresentation: {
                        switch failure.stablePresentation {
                        case .portrait:
                            dashboardSession.recover(using: .stayInPortrait)
                        case .dashboard:
                            dashboardSession.recover(using: .continueDashboard)
                        }
                    }
                )
            }

            if dashboardSession.isRestoringInactivePortrait {
                InactivePortraitRestorationOverlay()
            }

            if let message = dashboardSession.inactivePortraitFailureMessage {
                InactivePortraitRecoveryOverlay(
                    message: message,
                    onRetry: dashboardSession.retryInactivePortraitRestoration
                )
            }
        }
        .preferredColorScheme(appearancePreference.preferredColorScheme)
        .onChange(of: dashboardSession.restoredPortraitToken) { _, token in
            guard token != nil else { return }
            dashboardSession.consumeRestoredPortraitToken()
        }
    }

    private var appearancePreference: NembraAppearancePreference {
        NembraAppearancePreference(rawValue: appearanceRaw) ?? .nembraDark
    }

    private func openDashboard() {
        horizonCockpit.prepareForDashboardEntry()
        dashboardSession.beginEntry(preserving: DashboardPortraitRestorationToken())
    }

    private func closeDashboard() {
        dashboardSession.beginExit()
    }
}

private struct InactivePortraitRestorationOverlay: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            HStack(spacing: 12) {
                ProgressView()
                    .tint(NembraColor.gold)
                Text("Returning Home to portrait…")
                    .font(.headline)
                    .foregroundStyle(NembraColor.primaryText)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 58)
            .background(
                NembraColor.warmGraphite,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NembraColor.quietLine)
            }
            .padding(24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Returning Home to portrait")
        .accessibilityIdentifier("home.orientation.progress")
    }
}

private struct InactivePortraitRecoveryOverlay: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label("Home needs portrait", systemImage: "rectangle.portrait.rotate")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NembraColor.primaryText)

                Text(message)
                    .font(.body)
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try Again", action: onRetry)
                    .font(.headline)
                    .foregroundStyle(NembraColor.baseBlack)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        NembraColor.gold,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .accessibilityHint("Requests portrait orientation again.")
                    .accessibilityIdentifier("home.orientation.retry")
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(
                NembraColor.warmGraphite,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(NembraColor.quietLine)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.orientation.failure")
    }
}

private struct PortraitRootView: View {
    @Binding var selectedTab: NembraPrimaryTab
    let cockpit: HorizonCockpitStore
    let adaptiveRangeEstimate: NembraCore.AdaptiveBatteryRangeLiveEstimate?
    let onOpenNavigation: () -> Void
    let onOpenDashboard: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    cockpit: cockpit,
                    adaptiveRangeEstimate: adaptiveRangeEstimate,
                    onOpenRides: {
                        selectedTab = .rides
                    },
                    onOpenDashboard: onOpenDashboard
                )
                    // iOS 27's floating tab bar intentionally overlays the tab
                    // content. Give the Home scroll view extra safe-area room so
                    // its final vehicle row can scroll clear of that glass bar
                    // instead of sitting underneath an interactive control.
                    .safeAreaPadding(.bottom, 72)
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(NembraPrimaryTab.home)

            NavigationStack {
                RideHistoryView()
                    // Match Home's deliberate clearance for iOS 27's floating
                    // tab chrome. History rows remain reachable at the scroll end
                    // instead of terminating under navigation controls.
                    .safeAreaPadding(.bottom, 72)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onOpenNavigation) {
                                Label("Plan a ride", systemImage: "map")
                            }
                            .accessibilityHint("Search for a destination and preview it with Apple Maps.")
                            .accessibilityIdentifier("rides.plan-route")
                        }
                    }
            }
            .tabItem {
                Label("Rides", systemImage: "clock.arrow.circlepath")
            }
            .tag(NembraPrimaryTab.rides)

            NavigationStack {
                VehicleControlsView()
            }
            .tabItem {
                Label("Vehicle", systemImage: "scooter")
            }
            .tag(NembraPrimaryTab.vehicle)

            NavigationStack {
                NembraSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(NembraPrimaryTab.settings)
        }
        .tint(NembraColor.gold)
    }
}

private struct DashboardGeometryProgressOverlay: View {
    let isClosing: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()

            HStack(spacing: 12) {
                ProgressView()
                    .tint(NembraColor.gold)
                Text(isClosing ? "Returning to Home…" : "Opening Horizon…")
                    .font(.headline)
                    .foregroundStyle(NembraColor.primaryText)
            }
            .padding(.horizontal, 22)
            .frame(minHeight: 58)
            .background(
                NembraColor.warmGraphite,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(NembraColor.quietLine)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard.orientation.progress")
    }
}

private struct DashboardGeometryRecoveryOverlay: View {
    let failure: DashboardSessionFailure
    let message: String
    let allowsKeepingStablePresentation: Bool
    let onRetry: () -> Void
    let onKeepStablePresentation: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Label(recoveryTitle, systemImage: "rectangle.landscape.rotate")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(NembraColor.primaryText)

                Text(message)
                    .font(.body)
                    .foregroundStyle(NembraColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                GlassEffectContainer(spacing: 10) {
                    VStack(spacing: 10) {
                        Button("Try Again", action: onRetry)
                            .font(.headline)
                            .foregroundStyle(NembraColor.baseBlack)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                NembraColor.gold,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .accessibilityIdentifier("dashboard.orientation.retry")

                        if allowsKeepingStablePresentation {
                            Button(stableActionTitle, action: onKeepStablePresentation)
                                .font(.headline)
                                .foregroundStyle(NembraColor.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .nembraGlassControl()
                                .accessibilityIdentifier("dashboard.orientation.cancel")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(
                NembraColor.warmGraphite,
                in: RoundedRectangle(cornerRadius: 28, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(NembraColor.quietLine)
            }
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.orientation.failure")
    }

    private var recoveryTitle: String {
        switch failure.stablePresentation {
        case .portrait: "Horizon needs landscape"
        case .dashboard: "Home needs portrait"
        }
    }

    private var stableActionTitle: String {
        switch failure.stablePresentation {
        case .portrait: "Stay on Home"
        case .dashboard: "Continue Dashboard"
        }
    }
}

private struct RideHistoryView: View {
    @Environment(RideHistoryPresentationStore.self) private var history
    @Environment(RideApplicationStore.self) private var rides
    @Environment(DailyRidePresentationStore.self) private var daily
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var revealedDay: RideLocalDay?

    var body: some View {
        historyList
        .navigationTitle("Rides")
        .navigationBarTitleDisplayMode(.large)
        .task(id: rides.lastCompletedSessionID) {
            await history.refresh()
            await daily.refresh(currentRideSessionID: rides.activeSessionID)
        }
        .refreshable {
            await history.refresh()
            await daily.refresh(currentRideSessionID: rides.activeSessionID)
        }
    }

    @ViewBuilder
    private var emptyOrLoadingState: some View {
        switch history.status {
        case .idle, .loading:
            ProgressView("Loading rides…")
                .accessibilityIdentifier("rides.loading")
        case .ready:
            ContentUnavailableView(
                "No completed rides",
                systemImage: "clock.arrow.circlepath",
                description: Text("Completed rides appear here automatically after Nembra safely saves them.")
            )
            .accessibilityIdentifier("rides.empty")
        case .unavailable, .failed:
            ContentUnavailableView(
                "Ride history unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(history.lastErrorMessage ?? "Local ride history could not be opened safely.")
            )
            .accessibilityIdentifier("rides.error")
        }
    }

    private var historyList: some View {
        List {
            Section {
                archiveHeader
                    .listRowInsets(.init(top: 8, leading: 20, bottom: 14, trailing: 20))
            }
            .listRowBackground(NembraColor.baseBlack)
            .listRowSeparator(.hidden)

            Section {
                DailyMileageActivityView { day in
                    revealedDay = day
                }
                    .listRowInsets(.init(top: 0, leading: 20, bottom: 12, trailing: 20))
            }
            .listRowBackground(NembraColor.baseBlack)
            .listRowSeparator(.hidden)

            if history.status == .failed || history.status == .unavailable {
                Section {
                    Label(
                        history.lastErrorMessage ?? "Ride history could not be refreshed safely.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            if history.records.isEmpty {
                Section {
                    emptyOrLoadingState
                        .frame(maxWidth: .infinity, minHeight: 190)
                        .listRowBackground(NembraColor.baseBlack)
                }
            } else if displayedRecords.isEmpty, let revealedDay {
                Section {
                    ContentUnavailableView(
                        "No completed ride record yet",
                        systemImage: "clock.badge.questionmark",
                        description: Text(
                            "Accepted day totals can include a ride that is still active or waiting to finish saving."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } header: {
                    rideSectionHeader(for: revealedDay, count: 0)
                }
                .listRowBackground(NembraColor.baseBlack)
            } else {
                Section {
                    ForEach(displayedRecords, id: \.sessionID) { record in
                        NavigationLink {
                            RideHistoryDetailView(record: record)
                        } label: {
                            RideHistoryRowView(record: record)
                        }
                        .accessibilityIdentifier("rides.completed-row")
                        .listRowBackground(NembraColor.quietSurface)
                        .listRowSeparatorTint(NembraColor.quietLine)
                    }
                } header: {
                    rideSectionHeader(for: revealedDay, count: displayedRecords.count)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(NembraColor.baseBlack)
        .accessibilityIdentifier("rides.history")
    }

    private var savedRidesAccessibilityLabel: String {
        history.records.count == 1
            ? "1 saved ride"
            : "\(history.records.count) saved rides"
    }

    private var archiveHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    vehicleIdentity
                    monthSummary
                }
            } else {
                HStack(spacing: 14) {
                    vehicleIdentity
                    Spacer(minLength: 12)
                    monthSummary
                }
            }
        }
    }

    private var vehicleIdentity: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(NembraColor.deepGold.opacity(0.18))
                Circle()
                    .strokeBorder(NembraColor.gold.opacity(0.28), lineWidth: 1)
                Image(systemName: "scooter")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(NembraColor.primaryText)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayVehicleName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(NembraColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Circle()
                        .fill(archiveStatusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(archiveStatusText)
                        .font(.subheadline)
                        .foregroundStyle(NembraColor.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(displayVehicleName)
        .accessibilityValue(archiveStatusText)
    }

    private var monthSummary: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text(monthDistanceText)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(NembraColor.primaryText)
            Text(monthSummarySubtitle)
                .font(.caption)
                .foregroundStyle(NembraColor.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currentMonthName) accepted distance")
        .accessibilityValue(monthSummaryAccessibilityValue)
    }

    private func rideSectionHeader(for day: RideLocalDay?, count: Int) -> some View {
        HStack(spacing: 12) {
            Text(day.map { "Rides for \(shortDay($0))" } ?? "Saved rides")
            Spacer(minLength: 8)
            if day != nil {
                Button("All rides") {
                    revealedDay = nil
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(NembraColor.gold)
                .frame(minHeight: 44)
            } else {
                Text("\(count)")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            day == nil
                ? savedRidesAccessibilityLabel
                : "\(count) saved rides overlap \(day.map(shortDay) ?? "selected day")"
        )
    }

    private var displayedRecords: [RideHistoryRecord] {
        guard let revealedDay else { return history.records }
        return history.records.filter { record in
            record.evidence.beganAtDate < revealedDay.endDate
                && record.evidence.endedAtDate > revealedDay.startDate
        }
    }

    private var displayVehicleName: String {
        vehicle.profile == .simulatorQA
            ? VehicleProfile.aovoproES80.identity.displayName
            : vehicle.profile.identity.displayName
    }

    private var archiveStatusText: String {
        switch (history.status, daily.status) {
        case (.ready, .ready): "Ride history is current"
        case (.failed, _), (.unavailable, _), (_, .failed), (_, .unavailable):
            "Ride history needs attention"
        default: "Refreshing accepted history"
        }
    }

    private var archiveStatusColor: Color {
        switch (history.status, daily.status) {
        case (.ready, .ready): .green
        case (.failed, _), (.unavailable, _), (_, .failed), (_, .unavailable): .orange
        default: NembraColor.gold
        }
    }

    private var currentMonthInterval: DateInterval? {
        Calendar.current.dateInterval(of: .month, for: .now)
    }

    private var currentMonthSummaries: [DailyRideSummary] {
        guard let interval = currentMonthInterval else { return [] }
        return daily.recentDays.filter {
            $0.localDay.startDate < interval.end && $0.localDay.endDate > interval.start
        }
    }

    private var monthDistanceMeters: Double? {
        let values = currentMonthSummaries.compactMap { $0.distanceMeters.value }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private var monthDistanceIsPartial: Bool {
        currentMonthSummaries.contains {
            $0.rideCount > 0 && $0.distanceMeters.availability != .complete
        }
    }

    private var monthDistanceText: String {
        monthDistanceMeters.map {
            VehicleDisplayFormatting.distance(kilometers: $0 / 1_000)
        } ?? "—"
    }

    private var currentMonthName: String {
        Date.now.formatted(.dateTime.month(.wide))
    }

    private var monthSummarySubtitle: String {
        monthDistanceIsPartial ? "\(currentMonthName) · known" : currentMonthName
    }

    private var monthSummaryAccessibilityValue: String {
        guard monthDistanceMeters != nil else { return "No accepted distance evidence" }
        return monthDistanceIsPartial ? "\(monthDistanceText), known partial total" : monthDistanceText
    }

    private func shortDay(_ day: RideLocalDay) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: day.timeZoneIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: day.startDate)
    }
}

private struct RideHistoryRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: RideHistoryRecord

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    identityBlock
                    distanceBlock(alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    identityBlock
                    Spacer(minLength: 16)
                    distanceBlock(alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(rowAccessibilityValue)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(record.evidence.endedAtDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                if isRecovered {
                    Label("Recovered", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NembraColor.gold)
                }
            }
        }
    }

    @ViewBuilder
    private func distanceBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if let primaryDistance {
                Text(primaryDistance.value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(NembraColor.primaryText)
                Text(primaryDistance.source)
                    .font(.caption)
                    .foregroundStyle(NembraColor.secondaryText)
            }

            if !hasDistanceEvidence {
                Text("Distance unavailable")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryDistance: (source: String, value: String)? {
        if let odometerDeltaKilometers {
            return (
                "Scooter distance",
                VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers)
            )
        }
        guard record.evidence.qualityScreenedGPSDistanceMeters > 0 else { return nil }
        return (
            "GPS distance",
            VehicleDisplayFormatting.distance(
                kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
            )
        )
    }

    private var rowAccessibilityLabel: String {
        "Ride on \(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var rowAccessibilityValue: String {
        var parts = [record.evidence.endedAtDate.formatted(date: .omitted, time: .shortened)]
        if let odometerDeltaKilometers {
            parts.append(
                "scooter distance \(VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers))"
            )
        }
        if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
            parts.append(
                "GPS recorded distance \(VehicleDisplayFormatting.distance(kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000))"
            )
        }
        if !hasDistanceEvidence {
            parts.append("distance unavailable")
        }
        if isRecovered {
            parts.append("recovered after relaunch")
        }
        return parts.joined(separator: ", ")
    }

    private var isRecovered: Bool {
        record.evidence.continuity == .recoveredCheckpoint
    }

    private var hasDistanceEvidence: Bool {
        odometerDeltaKilometers != nil || record.evidence.qualityScreenedGPSDistanceMeters > 0
    }

    private var odometerDeltaKilometers: Double? {
        guard let start = record.evidence.startingOdometerKilometers,
              let end = record.evidence.endingOdometerKilometers,
              start.isFinite,
              end.isFinite,
              end > start else {
            return nil
        }
        return end - start
    }
}

private struct RideHistoryDetailView: View {
    @Environment(RideRoutePresentationStore.self) private var routes
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recordingDetailsExpanded = false

    let record: RideHistoryRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NembraMetrics.section) {
                rideHero
                routeSurface
                recordedDistanceSection
                timelineSection
                recordingDetailsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .safeAreaPadding(.bottom, 44)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Ride")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("rides.detail")
        .task(id: record.sessionID) {
            await routes.refresh(sessionID: record.sessionID)
        }
    }

    private var rideHero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(record.evidence.endedAtDate.formatted(date: .complete, time: .omitted))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            rideTimeAndRecovery
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var rideTimeAndRecovery: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                rideTime
                recoveredBadge
            }
        } else {
            HStack(spacing: 8) {
                rideTime
                recoveredBadge
            }
        }
    }

    private var rideTime: some View {
        Text(record.evidence.endedAtDate.formatted(date: .omitted, time: .shortened))
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var recoveredBadge: some View {
        if isRecovered {
            Label("Recovered", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var routeSurface: some View {
        if let geometry = routes.geometry(sessionID: record.sessionID) {
            if geometry.hasDrawablePath {
                VStack(alignment: .leading, spacing: 8) {
                    if dynamicTypeSize.isAccessibilitySize {
                        routeCoverageBadge(geometry.coverage)
                    }

                    ZStack(alignment: .topLeading) {
                        RideRouteMapView(geometry: geometry)
                            .frame(height: dynamicTypeSize.isAccessibilitySize ? 220 : 268)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Recorded ride route")
                            .accessibilityValue(routeAccessibilityValue(geometry))
                            .accessibilityHint("Shows only route points Nembra recorded for this ride.")
                            .accessibilityIdentifier("rides.route-map")

                        if !dynamicTypeSize.isAccessibilitySize {
                            routeCoverageBadge(geometry.coverage)
                                .padding(16)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
                }
            } else if geometry.hasRecordedGeometry {
                routeStateSurface(
                    title: "Route points saved",
                    systemImage: "mappin.and.ellipse",
                    message: "Recorded locations exist, but there are not enough continuous points to draw a route.",
                    identifier: "rides.route-points-only"
                )
            } else {
                routeUnavailableSurface
            }
        } else {
            switch routes.status(sessionID: record.sessionID) {
            case .idle, .loading:
                routeLoadingSurface
            case .unavailable:
                if routes.errorMessage(sessionID: record.sessionID) != nil {
                    routeStorageUnavailableSurface
                } else {
                    routeUnavailableSurface
                }
            case .failed:
                routeVerificationFailureSurface
            case .ready:
                routeUnavailableSurface
            }
        }
    }

    private func routeCoverageBadge(_ coverage: RideDistanceCoverage) -> some View {
        Text(routeCoverageLabel(coverage))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Color(uiColor: .systemBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    private var routeLoadingSurface: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading route…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .center)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
        )
        .accessibilityIdentifier("rides.route-loading")
    }

    private var routeUnavailableSurface: some View {
        routeStateSurface(
            title: "No route recorded",
            systemImage: "map",
            message: "No route points are available to draw for this ride.",
            identifier: "rides.route-unavailable"
        )
    }

    private var routeStorageUnavailableSurface: some View {
        routeStateSurface(
            title: "Route storage unavailable",
            systemImage: "externaldrive.badge.exclamationmark",
            message: "Saved route data is unavailable right now.",
            identifier: "rides.route-error"
        )
    }

    private var routeVerificationFailureSurface: some View {
        routeStateSurface(
            title: "Route could not be verified",
            systemImage: "exclamationmark.triangle",
            message: "Stored route data could not be verified safely.",
            identifier: "rides.route-error"
        )
    }

    private func routeStateSurface(
        title: String,
        systemImage: String,
        message: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var recordedDistanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recorded distance")

            VStack(spacing: 0) {
                if let odometerDeltaKilometers {
                    metricRow(
                        title: "Scooter",
                        subtitle: "Odometer change",
                        value: VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers),
                        systemImage: "scooter"
                    )
                    .accessibilityIdentifier("rides.evidence.odometer")
                }

                if hasMultipleDistanceSources {
                    Divider().padding(.leading, 56)
                }

                if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                    metricRow(
                        title: "GPS",
                        subtitle: "Quality-screened distance",
                        value: VehicleDisplayFormatting.distance(
                            kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
                        ),
                        systemImage: "location.fill"
                    )
                    .accessibilityIdentifier("rides.evidence.gps")
                }

                if !hasDistanceEvidence {
                    HStack(spacing: 12) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("No positive distance measurement is available for this ride.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(20)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
            )
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Ride window")

            VStack(spacing: 0) {
                timelineRow(title: "Started", date: record.evidence.beganAtDate)
                Divider().padding(.leading, 20)
                timelineRow(title: "Ended", date: record.evidence.endedAtDate)
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
            )
        }
    }

    private var recordingDetailsSection: some View {
        DisclosureGroup(isExpanded: $recordingDetailsExpanded) {
            VStack(spacing: 0) {
                recordingDetailRow("Ride confirmation", value: timestamp(record.evidence.confirmedAtDate))
                Divider().padding(.leading, 20)
                recordingDetailRow("Continuity", value: continuityDetailLabel)

                if let geometry = routes.geometry(sessionID: record.sessionID) {
                    Divider().padding(.leading, 20)
                    recordingDetailRow("Route recording", value: routeCoverageLabel(geometry.coverage))
                    Divider().padding(.leading, 20)
                    recordingDetailRow("Recorded points", value: "\(geometry.pointCount)")

                    if geometry.knownGapCount > 0 {
                        Divider().padding(.leading, 20)
                        recordingDetailRow("Known route gaps", value: "\(geometry.knownGapCount)")
                    }
                }

                if hasMultipleDistanceSources {
                    Text("Scooter and GPS distances are recorded independently.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text("Recording details")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .tint(.secondary)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
        )
        .accessibilityIdentifier("rides.recording-details")
    }

    @ViewBuilder
    private func metricRow(
        title: String,
        subtitle: String,
        value: String,
        systemImage: String
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        metricIcon(systemImage)
                        metricText(title: title, subtitle: subtitle)
                    }

                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                }
            } else {
                HStack(spacing: 16) {
                    metricIcon(systemImage)
                    metricText(title: title, subtitle: subtitle)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(value)
    }

    private func metricIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private func metricText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func timelineRow(title: String, date: Date) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: true, vertical: true)
                Spacer(minLength: 12)
                Text(timestamp(date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: true, vertical: true)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(timestamp(date))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 72)
        .padding(.vertical, 16)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recordingDetailRow(_ title: String, value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(value)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private var continuityDetailLabel: String {
        isRecovered ? "Recovered after relaunch" : "Continuous app session"
    }

    private func routeCoverageLabel(_ coverage: RideDistanceCoverage) -> String {
        switch coverage {
        case .complete:
            "Route coverage complete"
        case .partial:
            "Route coverage partial"
        case .unknown:
            "Route coverage unknown"
        }
    }

    private func routeAccessibilityValue(_ geometry: RideRouteGeometry) -> String {
        var parts = [routeCoverageLabel(geometry.coverage)]
        parts.append("\(geometry.pointCount) recorded points")
        switch geometry.knownGapCount {
        case 0:
            parts.append("no known route gaps recorded")
        case 1:
            parts.append("1 known route gap recorded")
        default:
            parts.append("\(geometry.knownGapCount) known route gaps recorded")
        }
        return parts.joined(separator: ", ")
    }

    private var isRecovered: Bool {
        record.evidence.continuity == .recoveredCheckpoint
    }

    private var hasDistanceEvidence: Bool {
        odometerDeltaKilometers != nil || record.evidence.qualityScreenedGPSDistanceMeters > 0
    }

    private var hasMultipleDistanceSources: Bool {
        odometerDeltaKilometers != nil && record.evidence.qualityScreenedGPSDistanceMeters > 0
    }

    private var odometerDeltaKilometers: Double? {
        guard let start = record.evidence.startingOdometerKilometers,
              let end = record.evidence.endingOdometerKilometers,
              start.isFinite,
              end.isFinite,
              end > start else {
            return nil
        }
        return end - start
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct RideRouteMapView: View {
    private struct PresentationSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }

    let geometry: RideRouteGeometry
    private let presentationSegments: [PresentationSegment]
    private let routeRegion: MKCoordinateRegion

    init(geometry: RideRouteGeometry) {
        self.geometry = geometry

        var projectedSegments: [PresentationSegment] = []
        projectedSegments.reserveCapacity(geometry.segments.count)

        var minimumLatitude: Double?
        var maximumLatitude: Double?
        var minimumLongitude: Double?
        var maximumLongitude: Double?

        for segment in geometry.segments {
            let coordinates = segment.points.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            if coordinates.count >= 2 {
                projectedSegments.append(PresentationSegment(id: Int(segment.index), coordinates: coordinates))
            }

            for point in segment.points {
                minimumLatitude = min(minimumLatitude ?? point.latitude, point.latitude)
                maximumLatitude = max(maximumLatitude ?? point.latitude, point.latitude)
                minimumLongitude = min(minimumLongitude ?? point.longitude, point.longitude)
                maximumLongitude = max(maximumLongitude ?? point.longitude, point.longitude)
            }
        }

        presentationSegments = projectedSegments

        if let minimumLatitude,
           let maximumLatitude,
           let minimumLongitude,
           let maximumLongitude {
            let center = CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.6, 0.002),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.6, 0.002)
            )
            routeRegion = MKCoordinateRegion(center: center, span: span)
        } else {
            routeRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
    }

    var body: some View {
        Map(initialPosition: .region(routeRegion)) {
            ForEach(presentationSegments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(Color(uiColor: .systemBackground), lineWidth: 8)
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(.primary, lineWidth: 4)
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            )
        )
    }
}
