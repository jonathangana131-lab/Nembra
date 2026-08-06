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
    let record: RideHistoryRecord

    var body: some View {
        List {
            Section("Ride timeline") {
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
                    Text(record.evidence.continuity == .recoveredCheckpoint
                         ? "Recovered after relaunch"
                         : "Uninterrupted process")
                }
            }

            Section {
                if let odometerDeltaKilometers {
                    LabeledContent("Scooter odometer delta") {
                        Text(VehicleDisplayFormatting.distance(kilometers: odometerDeltaKilometers))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("rides.evidence.odometer")
                }

                if record.evidence.qualityScreenedGPSDistanceMeters > 0 {
                    LabeledContent("GPS distance evidence") {
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
                    Text("No distance evidence was durably recorded for this ride.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Distance evidence")
            } footer: {
                Text("Nembra keeps independent sources separate until coverage can be reconciled. Neither value is silently promoted into a final ride distance.")
            }

            Section("Route") {
                Label("No route geometry recorded", systemImage: "map")
                    .font(.subheadline.weight(.semibold))
                Text("A map will appear only after Nembra has stored real quality-screened route points. This record contains no coordinates to draw truthfully.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("rides.route-unavailable")
            }
        }
        .navigationTitle("Ride Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("rides.detail")
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
