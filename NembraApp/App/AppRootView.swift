import MapKit
import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                DashboardView()
            } else {
                PortraitRootView()
            }
        }
    }
}

private struct PortraitRootView: View {
    @Environment(RideApplicationStore.self) private var rides

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    // iOS 27's floating tab bar intentionally overlays the tab
                    // content. Give the Home scroll view extra safe-area room so
                    // its final vehicle row can scroll clear of that glass bar
                    // instead of sitting underneath an interactive control.
                    .safeAreaPadding(.bottom, 72)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if rides.shouldPresentStatus {
                            RideStatusStrip()
                        }
                    }
            }
            .tabItem {
                Label("Home", systemImage: "scooter")
            }

            NavigationStack {
                RideHistoryView()
                    // Match Home's deliberate clearance for iOS 27's floating
                    // tab chrome. History rows remain reachable at the scroll end
                    // instead of terminating under navigation controls.
                    .safeAreaPadding(.bottom, 72)
            }
            .tabItem {
                Label("Rides", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

private struct RideStatusStrip: View {
    @Environment(RideApplicationStore.self) private var rides

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ride")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(rides.statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusForegroundStyle)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Automatic ride tracking")
        .accessibilityValue(rides.statusText)
        .accessibilityIdentifier("home.ride-status")
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch rides.status {
        case .restoring, .saving:
            ProgressView()
                .controlSize(.small)
        case .persistenceUnavailable, .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.red)
        case .temporarilyDisconnected:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
        case .candidate, .active, .endingCandidate:
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
        case .disabled, .idle:
            EmptyView()
        }
    }

    private var statusForegroundStyle: Color {
        switch rides.status {
        case .persistenceUnavailable, .failed:
            .red
        default:
            .primary
        }
    }
}

private struct RideHistoryView: View {
    @Environment(RideHistoryPresentationStore.self) private var history
    @Environment(RideApplicationStore.self) private var rides
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: NembraMetrics.section) {
                journalHeader

                if history.status == .failed || history.status == .unavailable {
                    journalStateSurface(
                        title: "Ride history unavailable",
                        systemImage: "exclamationmark.triangle",
                        message: history.lastErrorMessage ?? "Local ride history could not be opened safely.",
                        identifier: "rides.error"
                    )
                }

                if history.records.isEmpty {
                    emptyOrLoadingState
                } else {
                    savedRideJournal
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("Rides")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: rides.lastCompletedSessionID) {
            await history.refresh()
        }
        .refreshable {
            await history.refresh()
        }
        .accessibilityIdentifier("rides.history")
    }

    private var journalHeader: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 8) {
            Text("RIDE JOURNAL")
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Every ride, kept with its evidence.")
                .font(dynamicTypeSize.isAccessibilitySize ? .title2.weight(.bold) : .title.weight(.bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(savedRidesAccessibilityLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let mostRecentRideDate {
                    Text("Latest \(mostRecentRideDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text("Scooter odometer and GPS distance stay separate so the journal never turns one source into another.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ride journal")
        .accessibilityValue(savedRidesAccessibilityLabel)
        .accessibilityIdentifier("rides.journal-header")
    }

    @ViewBuilder
    private var emptyOrLoadingState: some View {
        switch history.status {
        case .idle, .loading:
            HStack(spacing: 14) {
                ProgressView()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Loading your journal")
                        .font(.headline)
                    Text("Checking saved ride evidence on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(journalSurface, in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
            .overlay {
                journalBorder(cornerRadius: NembraMetrics.heroRadius)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rides.loading")
        case .ready:
            journalStateSurface(
                title: "Your first ride belongs here",
                systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                message: "Completed rides appear automatically after Nembra safely saves their accepted recording evidence.",
                identifier: "rides.empty"
            )
        case .unavailable, .failed:
            EmptyView()
        }
    }

    private var savedRideJournal: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("SAVED RIDES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 12)

                Text("\(history.records.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 2)

            LazyVStack(spacing: 12) {
                ForEach(history.records, id: \.sessionID) { record in
                    NavigationLink {
                        RideHistoryDetailView(record: record)
                    } label: {
                        HStack(spacing: 14) {
                            RideHistoryRowView(record: record)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(dynamicTypeSize.isAccessibilitySize ? 18 : 20)
                        .background(journalSurface, in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous))
                        .overlay {
                            journalBorder(cornerRadius: NembraMetrics.controlRadius)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("rides.completed-row")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(savedRidesAccessibilityLabel)
    }

    private func journalStateSurface(
        title: String,
        systemImage: String,
        message: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(journalSurface, in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
        .overlay {
            journalBorder(cornerRadius: NembraMetrics.heroRadius)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var journalSurface: Color {
        reduceTransparency
            ? Color(uiColor: .secondarySystemBackground)
            : Color.primary.opacity(0.045)
    }

    private func journalBorder(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.primary.opacity(reduceTransparency ? 0.12 : 0.07))
    }

    private var mostRecentRideDate: Date? {
        history.records.first?.evidence.endedAtDate
    }

    private var savedRidesAccessibilityLabel: String {
        history.records.count == 1
            ? "1 saved ride"
            : "\(history.records.count) saved rides"
    }
}

private struct RideHistoryRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: RideHistoryRecord

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    identityBlock
                    evidenceDivider
                    distanceBlock(alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    identityBlock
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    distanceBlock(alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel)
        .accessibilityValue(rowAccessibilityValue)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .omitted))
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text(record.evidence.endedAtDate.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)

                if isRecovered {
                    Label("Recovered", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.055), in: Capsule())
                }
            }
        }
    }

    private var evidenceDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func distanceBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 7) {
            if let odometerDeltaKilometers {
                distanceLine(
                    label: "SCOOTER",
                    value: VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers)
                )
            }

            if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                distanceLine(
                    label: "GPS",
                    value: VehicleDisplayFormatting.distance(
                        kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
                    )
                )
            }

            if !hasDistanceEvidence {
                VStack(alignment: alignment, spacing: 2) {
                    Text("DISTANCE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.tertiary)
                    Text("Unavailable")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func distanceLine(label: String, value: String) -> some View {
        VStack(alignment: label == "SCOOTER" ? .trailing : .trailing, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.7)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                ZStack(alignment: .topLeading) {
                    RideRouteMapView(geometry: geometry)
                        .frame(height: 268)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recorded ride route")
                        .accessibilityValue(routeAccessibilityValue(geometry))
                        .accessibilityHint("Shows only route points Nembra recorded for this ride.")
                        .accessibilityIdentifier("rides.route-map")

                    Text(routeCoverageLabel(geometry.coverage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .padding(16)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(timestamp(date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer(minLength: 12)
                    Text(timestamp(date))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
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
