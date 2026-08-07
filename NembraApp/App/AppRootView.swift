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

    var body: some View {
        Group {
            if history.records.isEmpty {
                emptyOrLoadingState
            } else {
                historyList
            }
        }
        .navigationTitle("Rides")
        .task(id: rides.lastCompletedSessionID) {
            await history.refresh()
        }
        .refreshable {
            await history.refresh()
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
                description: Text("Safely saved rides will appear here. Nembra will not invent route or distance data that was never recorded.")
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
            if history.status == .failed || history.status == .unavailable {
                Section {
                    Label(
                        history.lastErrorMessage ?? "Ride history could not be refreshed safely.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(history.records, id: \.sessionID) { record in
                    NavigationLink {
                        RideHistoryDetailView(record: record)
                    } label: {
                        RideHistoryRowView(record: record)
                    }
                    .accessibilityIdentifier("rides.completed-row")
                }
            } footer: {
                Text("Distance sources stay separate until their coverage can be reconciled. A row never turns unreconciled evidence into a final ride total.")
            }
        }
        .accessibilityIdentifier("rides.history")
    }
}

private struct RideHistoryRowView: View {
    let record: RideHistoryRecord

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: record.evidence.continuity == .recoveredCheckpoint
                  ? "arrow.triangle.2.circlepath"
                  : "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text(continuityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 3) {
                if let odometerDeltaKilometers {
                    evidenceLine(
                        label: "ODO",
                        value: VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers)
                    )
                }

                if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                    evidenceLine(
                        label: "GPS",
                        value: VehicleDisplayFormatting.distance(
                            kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
                        )
                    )
                }

                if !hasDistanceEvidence {
                    Text("Distance —")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Completed ride")
        .accessibilityValue("\(record.evidence.endedAtDate.formatted(date: .abbreviated, time: .shortened)), \(distanceEvidenceAccessibilityValue), \(continuityLabel)")
    }

    private func evidenceLine(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var continuityLabel: String {
        record.evidence.continuity == .recoveredCheckpoint
            ? "Recovered ride"
            : "Completed ride"
    }

    private var hasDistanceEvidence: Bool {
        odometerDeltaKilometers != nil || record.evidence.qualityScreenedGPSDistanceMeters > 0
    }

    private var distanceEvidenceAccessibilityValue: String {
        var parts: [String] = []
        if let odometerDeltaKilometers {
            parts.append(
                "ODO evidence \(VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers))"
            )
        }
        if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
            parts.append(
                "GPS distance evidence \(VehicleDisplayFormatting.distance(kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000))"
            )
        }
        return parts.isEmpty ? "distance evidence unavailable" : parts.joined(separator: ", ")
    }

    private var odometerDeltaKilometers: Double? {
        guard let start = record.evidence.startingOdometerKilometers,
              let end = record.evidence.endingOdometerKilometers else {
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
            VStack(alignment: .leading, spacing: 6) {
                rideTime
                recoveredBadge
            }
        } else {
            HStack(spacing: 10) {
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
        if record.evidence.continuity == .recoveredCheckpoint {
            Label("Recovered", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var routeSurface: some View {
        if let geometry = routes.geometry(sessionID: record.sessionID) {
            if geometry.hasDrawablePath {
                ZStack(alignment: .bottomLeading) {
                    RideRouteMapView(geometry: geometry)
                        .frame(height: 268)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recorded ride route")
                        .accessibilityValue(routeAccessibilityValue(geometry))
                        .accessibilityIdentifier("rides.route-map")

                    Text(routeCoverageLabel(geometry.coverage))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .padding(14)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous))
            } else {
                routeStateSurface(
                    title: "Route points saved",
                    systemImage: "mappin.and.ellipse",
                    message: "This ride has recorded locations, but not enough continuous points to draw a route.",
                    identifier: "rides.route-points-only"
                )
            }
        } else {
            switch routes.status(sessionID: record.sessionID) {
            case .idle, .loading:
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
            case .unavailable:
                if routes.errorMessage(sessionID: record.sessionID) != nil {
                    routeErrorSurface
                } else {
                    routeUnavailableSurface
                }
            case .failed:
                routeErrorSurface
            case .ready:
                routeUnavailableSurface
            }
        }
    }

    private var routeUnavailableSurface: some View {
        routeStateSurface(
            title: "No route recorded",
            systemImage: "map",
            message: "A map appears only when real route points were saved for this ride.",
            identifier: "rides.route-unavailable"
        )
    }

    private var routeErrorSurface: some View {
        routeStateSurface(
            title: "Route unavailable",
            systemImage: "exclamationmark.triangle",
            message: "The saved route could not be opened safely.",
            identifier: "rides.route-error"
        )
    }

    private func routeStateSurface(
        title: String,
        systemImage: String,
        message: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: NembraMetrics.heroRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var recordedDistanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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

                if odometerDeltaKilometers != nil,
                   record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                    Divider().padding(.leading, 54)
                }

                if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                    metricRow(
                        title: "GPS",
                        subtitle: "Quality-screened route distance",
                        value: VehicleDisplayFormatting.distance(
                            kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
                        ),
                        systemImage: "location.fill"
                    )
                    .accessibilityIdentifier("rides.evidence.gps")
                }

                if odometerDeltaKilometers == nil,
                   record.evidence.qualityScreenedGPSDistanceMeters == 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                        Text("No distance measurement is available for this ride.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                }
            }
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
            )
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $recordingDetailsExpanded) {
                VStack(spacing: 0) {
                    recordingDetailRow("Ride confirmation", value: timestamp(record.evidence.confirmedAtDate))
                    Divider().padding(.leading, 20)
                    recordingDetailRow("Continuity", value: continuityDetailLabel)

                    if let geometry = routes.geometry(sessionID: record.sessionID) {
                        Divider().padding(.leading, 20)
                        recordingDetailRow("Map evidence", value: routeCoverageLabel(geometry.coverage))
                        Divider().padding(.leading, 20)
                        recordingDetailRow("Recorded points", value: "\(geometry.pointCount)")

                        if geometry.knownGapCount > 0 {
                            Divider().padding(.leading, 20)
                            recordingDetailRow("Known route gaps", value: "\(geometry.knownGapCount)")
                        }
                    }

                    Text("Scooter and GPS distances remain separate measurements unless a future reconciliation layer can prove they describe the same complete ride coverage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 18)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text("Recording details")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .tint(.secondary)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: NembraMetrics.controlRadius, style: .continuous)
            )
        }
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
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        metricIcon(systemImage)
                        metricText(title: title, subtitle: subtitle)
                    }

                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.leading)
                }
            } else {
                HStack(spacing: 14) {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(value)
    }

    private func metricIcon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26)
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
                VStack(alignment: .leading, spacing: 5) {
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
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func recordingDetailRow(_ title: String, value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
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
        .padding(.vertical, 13)
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
        record.evidence.continuity == .recoveredCheckpoint
            ? "Recovered after relaunch"
            : "Continuous app session"
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
        let gapDescription: String
        switch geometry.knownGapCount {
        case 0:
            gapDescription = "No known route gaps recorded"
        case 1:
            gapDescription = "1 known route gap recorded"
        default:
            gapDescription = "\(geometry.knownGapCount) known route gaps recorded"
        }
        return "\(routeCoverageLabel(geometry.coverage)). \(gapDescription)."
    }

    private var odometerDeltaKilometers: Double? {
        guard let start = record.evidence.startingOdometerKilometers,
              let end = record.evidence.endingOdometerKilometers,
              end >= start else {
            return nil
        }
        return end - start
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct RideRouteMapView: View {
    let geometry: RideRouteGeometry

    var body: some View {
        Map(initialPosition: .region(routeRegion)) {
            ForEach(geometry.segments, id: \.index) { segment in
                if segment.points.count >= 2 {
                    MapPolyline(coordinates: coordinates(for: segment))
                        .stroke(.primary, lineWidth: 4)
                }
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

    private func coordinates(for segment: RideRouteSegment) -> [CLLocationCoordinate2D] {
        segment.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    private var routeRegion: MKCoordinateRegion {
        let allPoints = geometry.segments.flatMap(\.points)
        guard let first = allPoints.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }

        var minimumLatitude = first.latitude
        var maximumLatitude = first.latitude
        var minimumLongitude = first.longitude
        var maximumLongitude = first.longitude
        for point in allPoints.dropFirst() {
            minimumLatitude = min(minimumLatitude, point.latitude)
            maximumLatitude = max(maximumLatitude, point.latitude)
            minimumLongitude = min(minimumLongitude, point.longitude)
            maximumLongitude = max(maximumLongitude, point.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.6, 0.002),
            longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.6, 0.002)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
