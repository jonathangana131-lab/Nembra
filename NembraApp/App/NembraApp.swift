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

private struct NembraNavigationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selectedItem: MKMapItem?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isSearching = false
    @State private var searchError: String?

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
            ContentUnavailableView(
                "Find a destination",
                systemImage: "magnifyingglass",
                description: Text("Search for a place or address. Nembra will preview it here without using scooter telemetry.")
            )
            .frame(maxWidth: .infinity, minHeight: 230)
            .accessibilityIdentifier("navigation.empty")
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name ?? "Unnamed place")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let address = item.placemark.title {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("navigation.result")
            }
            .listStyle(.plain)
        }
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
        cameraPosition = .region(
            MKCoordinateRegion(
                center: item.placemark.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
    }

    private func openDirections(to item: MKMapItem) {
        item.openInMaps(
            launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ]
        )
    }
}
