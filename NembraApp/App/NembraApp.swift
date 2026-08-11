import Foundation
import MapKit
import SwiftUI

@main
struct NembraApp: App {
    @State private var runtime = AppBootstrap.makeRuntime()

    var body: some Scene {
        WindowGroup {
            NembraNavigationHost {
                AppRootView()
                    .environment(runtime.vehicleStore)
                    .environment(runtime.rideStore)
                    .environment(runtime.rideHistoryStore)
                    .environment(runtime.rideRouteStore)
                    .task { await runtime.start() }
            }
            .environment(runtime.vehicleStore)
        }
    }
}

private struct NembraNavigationHost<Content: View>: View {
    @Environment(VehicleStore.self) private var vehicle
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isNavigationPresented = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            content

            if shouldShowNavigationLauncher {
                navigationLauncher
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: launcherAlignment)
                    .padding(.top, verticalSizeClass == .compact ? 10 : 0)
                    .padding(.trailing, verticalSizeClass == .compact ? 0 : 18)
                    .padding(.bottom, verticalSizeClass == .compact ? 0 : 92)
            }
        }
        .sheet(isPresented: $isNavigationPresented) {
            NavigationStack {
                NembraNavigationView()
            }
        }
    }

    private var shouldShowNavigationLauncher: Bool {
        guard verticalSizeClass == .compact else { return true }
        guard let speed = vehicle.simulatorQualifiedLiveSpeedKilometersPerHour else { return false }
        return speed < 0.5
    }

    private var launcherAlignment: Alignment {
        verticalSizeClass == .compact ? .top : .bottomTrailing
    }

    private var navigationLauncher: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                isNavigationPresented = true
            }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Label("Navigation", systemImage: "location.north.circle.fill")
                        .font(.headline)
                        .padding(.horizontal, 18)
                } else {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                }
            }
            .frame(minWidth: 54, minHeight: 54)
            .background {
                if reduceTransparency {
                    Color(uiColor: .secondarySystemBackground)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12))
            }
            .shadow(radius: reduceTransparency ? 3 : 8, y: reduceTransparency ? 2 : 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Navigation")
        .accessibilityHint(
            verticalSizeClass == .compact
                ? "Available while current stopped speed is confirmed. Search for a destination and preview it on the map."
                : "Search for a destination and preview it on the map."
        )
        .accessibilityIdentifier("navigation.launch")
    }
}

private struct NembraRecentDestination: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let address: String?
    let latitude: Double
    let longitude: Double

    init(item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Destination"
        address = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        latitude = coordinate.latitude
        longitude = coordinate.longitude
        id = "\(latitude.rounded(toPlaces: 5)),\(longitude.rounded(toPlaces: 5))"
    }

    var mapItem: MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = name
        return item
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

private struct NembraNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("navigation.recentDestinations.v1") private var recentDestinationsJSON = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedItem: MKMapItem?
    @State private var selectedAddress: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isClearRecentsConfirmationPresented = false

    private var recentDestinations: [NembraRecentDestination] {
        guard let data = recentDestinationsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([NembraRecentDestination].self, from: data) else {
            return []
        }
        return decoded
    }

    var body: some View {
        VStack(spacing: 0) {
            destinationMap

            Divider()

            searchSurface
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .searchable(text: $query, prompt: "Search destinations")
        .onChange(of: query) { _, _ in
            guard selectedItem != nil else { return }
            selectedItem = nil
            selectedAddress = nil
            cameraPosition = .automatic
        }
        .task(id: query) {
            await searchDestinations()
        }
        .confirmationDialog(
            "Clear all recent destinations?",
            isPresented: $isClearRecentsConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear Recent Destinations", role: .destructive) {
                clearRecentDestinations()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all recent destinations stored on this device.")
        }
        .accessibilityIdentifier("navigation.surface")
    }

    private var destinationMap: some View {
        Map(position: $cameraPosition) {
            if let selectedItem {
                Marker(
                    selectedItem.name ?? "Destination",
                    coordinate: selectedItem.placemark.coordinate
                )
            }
        }
        .mapStyle(
            .standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .all,
                showsTraffic: true
            )
        )
        .frame(height: navigationMapHeight)
        .overlay(alignment: .topLeading) {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItem.name ?? "Destination")
                        .font(.headline)
                        .lineLimit(1)

                    if let subtitle = selectedAddress ?? selectedItem.placemark.title,
                       subtitle != selectedItem.name {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.primary.opacity(0.10))
                }
                .padding(16)
                .accessibilityElement(children: .combine)
            } else {
                Label("MAP PREVIEW", systemImage: "scope")
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background {
                        if reduceTransparency {
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        } else {
                            Capsule(style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.primary.opacity(0.10))
                    }
                    .padding(14)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("navigation.map")
    }

    private var navigationMapHeight: CGFloat {
        if verticalSizeClass == .compact {
            return dynamicTypeSize.isAccessibilitySize ? 160 : 180
        }
        return dynamicTypeSize.isAccessibilitySize ? 220 : 280
    }

    @ViewBuilder
    private var searchSurface: some View {
        if let selectedItem {
            selectedDestinationCard(selectedItem)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if recentDestinations.isEmpty {
                navigationEmptyState
            } else {
                recentDestinationList
            }
        } else if isSearching {
            navigationStatusSurface(
                eyebrow: "SEARCHING MAP",
                title: "Looking for places",
                detail: "Map results stay separate from scooter telemetry.",
                systemImage: "location.magnifyingglass",
                showsProgress: true,
                identifier: "navigation.searching"
            )
        } else if let searchError {
            navigationStatusSurface(
                eyebrow: "MAP SEARCH",
                title: "Navigation unavailable",
                detail: searchError,
                systemImage: "exclamationmark.triangle",
                identifier: "navigation.error"
            )
        } else if results.isEmpty {
            navigationStatusSurface(
                eyebrow: "MAP SEARCH",
                title: "No destination found",
                detail: "Try a more specific place or address.",
                systemImage: "location.slash",
                identifier: "navigation.no-results"
            )
        } else {
            List(results, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    destinationRow(
                        name: item.name ?? "Unnamed place",
                        address: item.placemark.title
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("navigation.result")
            }
            .listStyle(.plain)
        }
    }

    private var navigationEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("NAVIGATION")
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(.secondary)

            Text("Find a destination")
                .font(.largeTitle.weight(.semibold))
                .tracking(-0.7)

            Text("Search for a place or address. Nembra will preview it here without using scooter telemetry.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 9) {
                Circle()
                    .fill(.primary)
                    .frame(width: 6, height: 6)

                Capsule(style: .continuous)
                    .fill(.primary.opacity(0.16))
                    .frame(height: 2)

                Image(systemName: "location.north.fill")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Label("Choose a destination before riding.", systemImage: "hand.raised.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, verticalSizeClass == .compact ? 14 : 22)
        .frame(
            maxWidth: .infinity,
            minHeight: verticalSizeClass == .compact ? 150 : 230,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("navigation.empty")
    }

    private func navigationStatusSurface(
        eyebrow: String,
        title: String,
        detail: String,
        systemImage: String,
        showsProgress: Bool = false,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }

                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.5)
            }
            .foregroundStyle(.secondary)

            Text(title)
                .font(.title2.weight(.semibold))

            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, verticalSizeClass == .compact ? 14 : 22)
        .frame(
            maxWidth: .infinity,
            minHeight: verticalSizeClass == .compact ? 150 : 230,
            alignment: .topLeading
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var recentDestinationList: some View {
        List {
            Section {
                ForEach(recentDestinations) { destination in
                    Button {
                        selectRecent(destination)
                    } label: {
                        destinationRow(name: destination.name, address: destination.address)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("navigation.recent")
                }
                .onDelete(perform: deleteRecentDestinations)

                Button(role: .destructive) {
                    isClearRecentsConfirmationPresented = true
                } label: {
                    Label("Clear Recent Destinations", systemImage: "trash")
                }
                .accessibilityIdentifier("navigation.recents.clear")
            } header: {
                Text("Recent destinations")
            } footer: {
                Text("Recent places are stored on this device. Swipe a place to remove it, or clear the list. They do not contain scooter telemetry.")
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("navigation.recents")
    }

    private func destinationRow(name: String, address: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.headline)
                .foregroundStyle(.primary)

            if let address {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func selectedDestinationCard(_ item: MKMapItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name ?? "Destination")
                        .font(.title2.weight(.semibold))

                    if let address = selectedAddress ?? item.placemark.title {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    openDirections(to: item)
                } label: {
                    Label("Directions in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("navigation.directions")

                Button("Choose another destination") {
                    selectedItem = nil
                    selectedAddress = nil
                    cameraPosition = .automatic
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("navigation.change-destination")

                Label(
                    "Route guidance is handed off to Apple Maps. Nembra does not claim a road or path is scooter-legal or safe; follow local rules and posted signs.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("navigation.destination")
    }

    @MainActor
    private func searchDestinations() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            selectedItem = nil
            selectedAddress = nil
            searchError = nil
            isSearching = false
            return
        }

        // Clear the prior provider response before the debounce. Otherwise a new
        // non-empty query can temporarily display MapKit results from the old query.
        results = []
        searchError = nil
        isSearching = true

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = Array(response.mapItems.prefix(12))
            isSearching = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            isSearching = false
            searchError = "Places could not be loaded right now. Check the network connection and try again."
        }
    }

    private func select(_ item: MKMapItem) {
        selectedItem = item
        selectedAddress = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        remember(item)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: item.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    private func selectRecent(_ destination: NembraRecentDestination) {
        selectedItem = destination.mapItem
        selectedAddress = destination.address
        promoteRecent(destination)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    private func remember(_ item: MKMapItem) {
        promoteRecent(NembraRecentDestination(item: item))
    }

    private func promoteRecent(_ recent: NembraRecentDestination) {
        var updated = recentDestinations.filter { $0.id != recent.id }
        updated.insert(recent, at: 0)
        updated = Array(updated.prefix(6))
        persistRecentDestinations(updated)
    }

    private func deleteRecentDestinations(at offsets: IndexSet) {
        var updated = recentDestinations
        updated.remove(atOffsets: offsets)
        persistRecentDestinations(updated)
    }

    private func clearRecentDestinations() {
        recentDestinationsJSON = ""
    }

    private func persistRecentDestinations(_ destinations: [NembraRecentDestination]) {
        guard !destinations.isEmpty else {
            recentDestinationsJSON = ""
            return
        }

        guard let data = try? JSONEncoder().encode(destinations),
              let encoded = String(data: data, encoding: .utf8) else {
            return
        }
        recentDestinationsJSON = encoded
    }

    private func openDirections(to item: MKMapItem) {
        item.openInMaps()
    }
}
