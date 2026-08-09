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
        }
    }
}

private struct NembraNavigationHost<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isNavigationPresented = false

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            if verticalSizeClass != .compact {
                Button {
                    isNavigationPresented = true
                } label: {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(0.08))
                        }
                        .shadow(radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 92)
                .accessibilityLabel("Navigation")
                .accessibilityHint("Search for a destination and preview it on the map.")
                .accessibilityIdentifier("navigation.launch")
            }
        }
        .sheet(isPresented: $isNavigationPresented) {
            NavigationStack {
                NembraNavigationView()
            }
        }
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
    @AppStorage("navigation.recentDestinations.v1") private var recentDestinationsJSON = ""
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedItem: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var searchError: String?

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
        .task(id: query) {
            await searchDestinations()
        }
        .accessibilityIdentifier("navigation.root")
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
        .frame(minHeight: 280)
        .overlay(alignment: .topLeading) {
            if let selectedItem {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItem.name ?? "Destination")
                        .font(.headline)
                        .lineLimit(1)

                    if let subtitle = selectedItem.placemark.title,
                       subtitle != selectedItem.name {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(16)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("navigation.map")
    }

    @ViewBuilder
    private var searchSurface: some View {
        if let selectedItem {
            selectedDestinationCard(selectedItem)
        } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if recentDestinations.isEmpty {
                ContentUnavailableView(
                    "Find a destination",
                    systemImage: "magnifyingglass",
                    description: Text("Search for a place or address. Nembra will preview it here without using scooter telemetry.")
                )
                .frame(maxWidth: .infinity, minHeight: 230)
                .accessibilityIdentifier("navigation.empty")
            } else {
                recentDestinationList
            }
        } else if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, minHeight: 230)
                .accessibilityIdentifier("navigation.searching")
        } else if let searchError {
            ContentUnavailableView(
                "Search unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(searchError)
            )
            .frame(maxWidth: .infinity, minHeight: 230)
            .accessibilityIdentifier("navigation.error")
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxWidth: .infinity, minHeight: 230)
                .accessibilityIdentifier("navigation.no-results")
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
                    clearRecentDestinations()
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

                    if let address = item.placemark.title {
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
            searchError = nil
            isSearching = false
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isSearching = true
        searchError = nil

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
        remember(destination.mapItem)
        cameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    private func remember(_ item: MKMapItem) {
        let recent = NembraRecentDestination(item: item)
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
