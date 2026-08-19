import Foundation
import MapKit
import NembraCore
import Observation

enum HorizonMapPolylineRole: String, Equatable, Sendable {
    case navigationRoute
    case eligibleUnexplored
    case acceptedHistoricalCoverage
    case currentDiscovery
}

struct HorizonMapCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    var mapCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct HorizonMapPolyline: Identifiable, Equatable, Sendable {
    let id: String
    let role: HorizonMapPolylineRole
    let coordinates: [HorizonMapCoordinate]

    init?(id: String, role: HorizonMapPolylineRole, coordinates: [HorizonMapCoordinate]) {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty, coordinates.count >= 2 else { return nil }
        self.id = normalizedID
        self.role = role
        self.coordinates = coordinates
    }
}

enum HorizonMapGeometryBinding: Equatable, Sendable {
    case navigation(HorizonNavigationRouteReference)
    case exploration(RoadDatasetKey)
}

/// Vector geometry resolved by the MapKit/road-provider adapter for one fenced
/// Horizon overlay request. This is rendering input only; it cannot create a
/// navigation route or verified road-coverage claim.
struct HorizonMapOverlaySnapshot: Equatable, Sendable {
    let request: HorizonOverlayRequestToken
    let binding: HorizonMapGeometryBinding
    let polylines: [HorizonMapPolyline]
    let currentPosition: HorizonMapCoordinate?

    init(
        request: HorizonOverlayRequestToken,
        binding: HorizonMapGeometryBinding,
        polylines: [HorizonMapPolyline],
        currentPosition: HorizonMapCoordinate?
    ) {
        self.request = request
        self.binding = binding
        self.polylines = polylines
        self.currentPosition = currentPosition
    }
}

/// Platform adapter boundary. Implementations may query MapKit or an approved,
/// versioned road provider off the main actor, but must return geometry bound to
/// the exact request token and domain snapshot they received.
protocol HorizonMapOverlayGeometryProvider: Sendable {
    func navigationGeometry(
        for snapshot: HorizonNavigationOverlaySnapshot,
        request: HorizonOverlayRequestToken
    ) async throws -> HorizonMapOverlaySnapshot

    func explorationGeometry(
        for snapshot: HorizonExplorationOverlaySnapshot,
        request: HorizonOverlayRequestToken
    ) async throws -> HorizonMapOverlaySnapshot
}

/// Root-owned, composition-neutral cockpit presentation state. It owns no
/// telemetry and no map evidence.
/// Its responsibilities are limited to shared battery preference, cockpit mode,
/// semantic reflow, and exact request fencing for async overlay geometry.
@MainActor
@Observable
final class HorizonCockpitStore {
    private(set) var coordinator: HorizonPresentationCoordinator
    private(set) var navigationGeometry: HorizonMapOverlaySnapshot?
    private(set) var explorationGeometry: HorizonMapOverlaySnapshot?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let batteryModeKey: String

    init(
        defaults: UserDefaults = .standard,
        batteryModeKey: String = "horizon.batteryPrimaryReadout.v1"
    ) {
        self.defaults = defaults
        self.batteryModeKey = batteryModeKey
        let restoredMode = defaults.string(forKey: batteryModeKey)
            .flatMap(BatteryPrimaryReadoutMode.init(rawValue:))
            ?? .percentage
        coordinator = HorizonPresentationCoordinator(
            presentationContextID: UUID(),
            initialMode: .drive,
            batteryPrimaryReadoutState: BatteryPrimaryReadoutState(mode: restoredMode)
        )
    }

    var mode: HorizonCockpitMode { coordinator.mode }
    var reflow: HorizonCockpitReflow { coordinator.reflow }
    var batteryPrimaryReadoutState: BatteryPrimaryReadoutState {
        coordinator.batteryPrimaryReadoutState
    }

    func prepareForDashboardEntry() {
        _ = try? coordinator.selectMode(.drive)
        navigationGeometry = nil
        explorationGeometry = nil
    }

    func selectMode(_ mode: HorizonCockpitMode) {
        guard (try? coordinator.selectMode(mode)) != nil else { return }
        navigationGeometry = nil
        explorationGeometry = nil
    }

    func toggleBatteryPrimaryReadout() {
        let mode = coordinator.toggleBatteryPrimaryReadout()
        defaults.set(mode.rawValue, forKey: batteryModeKey)
    }

    func beginOverlayRequest(for kind: HorizonOverlayKind) -> HorizonOverlayRequestToken? {
        try? coordinator.beginOverlayRequest(for: kind)
    }

    @discardableResult
    func applyNavigation(
        request: HorizonOverlayRequestToken,
        presentation: HorizonNavigationOverlayPresentation,
        geometry: HorizonMapOverlaySnapshot?
    ) -> HorizonOverlayApplyResult {
        if case let .authoritative(snapshot) = presentation {
            guard geometry?.request == request,
                  geometry?.binding == .navigation(snapshot.route) else {
                return .rejectedStale
            }
        } else if geometry != nil {
            return .rejectedStale
        }

        let result = coordinator.applyNavigationUpdate(
            HorizonNavigationOverlayUpdate(request: request, presentation: presentation)
        )
        if result == .applied {
            navigationGeometry = geometry
        }
        return result
    }

    @discardableResult
    func applyExploration(
        request: HorizonOverlayRequestToken,
        presentation: HorizonExplorationOverlayPresentation,
        geometry: HorizonMapOverlaySnapshot?
    ) -> HorizonOverlayApplyResult {
        if case let .authoritative(snapshot) = presentation {
            guard geometry?.request == request,
                  geometry?.binding == .exploration(snapshot.datasetKey) else {
                return .rejectedStale
            }
        } else if geometry != nil {
            return .rejectedStale
        }

        let result = coordinator.applyExplorationUpdate(
            HorizonExplorationOverlayUpdate(request: request, presentation: presentation)
        )
        if result == .applied {
            explorationGeometry = geometry
        }
        return result
    }

}
