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

    var body: some View {
        Group {
            if history.records.isEmpty {
                emptyOrLoadingState
            } else {
                historyList
            }
        }
        .navigationTitle("Rides")
        .navigationBarTitleDisplayMode(.large)
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

            Section {
                ForEach(history.records, id: \.sessionID) { record in
                    NavigationLink {
                        RideHistoryDetailView(record: record)
                    } label: {
                        RideHistoryRowView(record: record)
                    }
                    .accessibilityIdentifier("rides.completed-row")
                }
            } header: {
                HStack {
                    Text("Saved rides")
                    Spacer()
                    Text("\(history.records.count)")
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(savedRidesAccessibilityLabel)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("rides.history")
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
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func distanceBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            if let odometerDeltaKilometers {
                distanceLine(
                    label: "Scooter",
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
                Text("Distance unavailable")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func distanceLine(label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
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
              let end = record.evidence.endingOdometerKilometers else {
            return nil
        }
        return end - start
    }
}

private struct RideHistoryDetailView: View {
    @Environment(RideRoutePresentationStore.self) private var routes
    @State private var recordingDetailsExpanded = false
    let record: RideHistoryRecord

    var body: some View {
        List {
            summarySection
            routeSection
            distanceSection
            recordingDetailsSection
        }
        .navigationTitle("Ride Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("rides.detail")
        .task(id: record.sessionID) {
            await routes.refresh(sessionID: record.sessionID)
        }
    }

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(record.evidence.endedAtDate.formatted(date: .complete, time: .omitted))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text(record.evidence.endedAtDate.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if isRecovered {
                        Label("Recovered", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        Section("Route") {
            if let geometry = routes.geometry(sessionID: record.sessionID) {
                if geometry.hasDrawablePath {
                    RideRouteMapView(geometry: geometry)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Recorded ride route")
                        .accessibilityValue(routeAccessibilityValue(geometry))
                        .accessibilityHint("Shows only route points Nembra recorded for this ride.")
                        .accessibilityIdentifier("rides.route-map")
                } else {
                    Label("Route points recorded", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                    Text("Recorded coordinates exist, but there are not enough continuous points to draw a route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("rides.route-points-only")
                }

                DisclosureGroup("Route recording") {
                    LabeledContent("Coverage") {
                        Text(routeCoverageLabel(geometry.coverage))
                    }
                    LabeledContent("Recorded points") {
                        Text("\(geometry.pointCount)")
                            .monospacedDigit()
                    }
                    if geometry.knownGapCount > 0 {
                        LabeledContent("Known gaps") {
                            Text("\(geometry.knownGapCount)")
                                .monospacedDigit()
                        }
                    }
                }
            } else {
                switch routes.status(sessionID: record.sessionID) {
                case .idle, .loading:
                    ProgressView("Loading route…")
                        .accessibilityIdentifier("rides.route-loading")
                case .unavailable:
                    if let message = routes.errorMessage(sessionID: record.sessionID) {
                        routeErrorContent(message)
                    } else {
                        routeUnavailableContent
                    }
                case .failed:
                    routeErrorContent(
                        routes.errorMessage(sessionID: record.sessionID)
                            ?? "Stored route geometry could not be verified safely."
                    )
                case .ready:
                    routeUnavailableContent
                }
            }
        }
    }

    private var distanceSection: some View {
        Section {
            if let odometerDeltaKilometers {
                LabeledContent("Scooter distance") {
                    Text(VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("rides.evidence.odometer")
            }

            if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                LabeledContent("GPS recorded distance") {
                    Text(
                        VehicleDisplayFormatting.distance(
                            kilometers: record.evidence.qualityScreenedGPSDistanceMeters / 1_000
                        )
                    )
                    .monospacedDigit()
                }
                .accessibilityIdentifier("rides.evidence.gps")
            }

            if odometerDeltaKilometers == nil,
               record.evidence.qualityScreenedGPSDistanceMeters == 0 {
                Text("No distance was durably recorded for this ride.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Distance")
        } footer: {
            if hasMultipleDistanceSources {
                Text("Scooter and GPS are recorded independently.")
            }
        }
    }

    private var recordingDetailsSection: some View {
        Section {
            DisclosureGroup("Recording details", isExpanded: $recordingDetailsExpanded) {
                LabeledContent("Started") {
                    Text(timestamp(record.evidence.beganAtDate))
                }
                LabeledContent("Confirmed") {
                    Text(timestamp(record.evidence.confirmedAtDate))
                }
                LabeledContent("Ended") {
                    Text(timestamp(record.evidence.endedAtDate))
                }
                LabeledContent("Continuity") {
                    Text(isRecovered ? "Recovered after relaunch" : "Uninterrupted process")
                }
            }
        }
    }

    private var routeUnavailableContent: some View {
        Group {
            Label("No route recorded", systemImage: "map")
                .font(.subheadline.weight(.semibold))
            Text("This ride has no stored coordinates to draw.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rides.route-unavailable")
        }
    }

    private func routeErrorContent(_ message: String) -> some View {
        Group {
            Label("Route storage unavailable", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rides.route-error")
        }
    }

    private func routeAccessibilityValue(_ geometry: RideRouteGeometry) -> String {
        var parts = [routeCoverageLabel(geometry.coverage)]
        parts.append("\(geometry.pointCount) recorded points")
        if geometry.knownGapCount > 0 {
            let noun = geometry.knownGapCount == 1 ? "known gap" : "known gaps"
            parts.append("\(geometry.knownGapCount) \(noun)")
        }
        return parts.joined(separator: ", ")
    }

    private func routeCoverageLabel(_ coverage: RideDistanceCoverage) -> String {
        switch coverage {
        case .complete:
            "Complete recorded coverage"
        case .partial:
            "Partial recorded coverage"
        case .unknown:
            "Coverage unknown"
        }
    }

    private var isRecovered: Bool {
        record.evidence.continuity == .recoveredCheckpoint
    }

    private var hasMultipleDistanceSources: Bool {
        odometerDeltaKilometers != nil && record.evidence.qualityScreenedGPSDistanceMeters > 0
    }

    private var odometerDeltaKilometers: Double? {
        guard let start = record.evidence.startingOdometerKilometers,
              let end = record.evidence.endingOdometerKilometers else {
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
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 8)
                    MapPolyline(coordinates: coordinates(for: segment))
                        .stroke(.primary, lineWidth: 4)
                }
            }
        }
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