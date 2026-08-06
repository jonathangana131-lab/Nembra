public enum NavigationRouteContractError: Error, Equatable, Sendable {
    case invalidLatitude
    case invalidLongitude
    case invalidRouteDistance
    case invalidExpectedTravelTime
    case invalidStepDistance
    case emptyRouteGeometry
    case emptyRouteSteps
}

/// A framework-neutral coordinate used at the MapKit/domain boundary.
///
/// This type is route-planning/guidance input only. Constructing one does not make it
/// ride-location evidence and map matching must never feed it back into ride distance truth.
public struct NavigationCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, (-90.0...90.0).contains(latitude) else {
            throw NavigationRouteContractError.invalidLatitude
        }
        guard longitude.isFinite, (-180.0...180.0).contains(longitude) else {
            throw NavigationRouteContractError.invalidLongitude
        }
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// The routing category actually requested from the route provider.
///
/// `cycling` means a cycling-based route suggestion. It is not a scooter-legality,
/// access, surface, or safety classification.
public enum NavigationRouteTransportBasis: String, Equatable, Sendable {
    case cycling
}

public struct NavigationRouteRequestIntent: Equatable, Sendable {
    public let origin: NavigationCoordinate
    public let destination: NavigationCoordinate
    public let transportBasis: NavigationRouteTransportBasis
    public let requestsAlternateRoutes: Bool

    public init(
        origin: NavigationCoordinate,
        destination: NavigationCoordinate,
        transportBasis: NavigationRouteTransportBasis = .cycling,
        requestsAlternateRoutes: Bool = false
    ) {
        self.origin = origin
        self.destination = destination
        self.transportBasis = transportBasis
        self.requestsAlternateRoutes = requestsAlternateRoutes
    }
}

/// Explicit provenance for an immutable route projection.
///
/// The current production candidate is Apple MapKit cycling directions. This provenance
/// never implies that any segment is legal, permitted, or safe for an AOVOPRO ES80.
public enum NavigationRouteProvenance: String, Equatable, Sendable {
    case appleMapKitCycling
}

public struct NavigationRouteStepSnapshot: Equatable, Sendable {
    public let instruction: String
    public let notice: String?
    public let distanceMeters: Double
    public let geometry: [NavigationCoordinate]

    public init(
        instruction: String,
        notice: String?,
        distanceMeters: Double,
        geometry: [NavigationCoordinate]
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw NavigationRouteContractError.invalidStepDistance
        }

        self.instruction = instruction
        self.notice = notice
        self.distanceMeters = distanceMeters
        self.geometry = geometry
    }
}

/// Framework-neutral, immutable route data projected from the route provider.
///
/// Localized provider strings are preserved as-is. This type deliberately has no inferred
/// maneuver enum and no scooter-legality/safety field because neither may be derived from
/// instruction text or MapKit cycling provenance alone.
public struct NavigationRouteSnapshot: Equatable, Sendable {
    public let provenance: NavigationRouteProvenance
    public let distanceMeters: Double
    public let expectedTravelTimeSeconds: Double
    public let geometry: [NavigationCoordinate]
    public let steps: [NavigationRouteStepSnapshot]
    public let advisoryNotices: [String]
    public let hasHighways: Bool
    public let hasTolls: Bool

    public init(
        provenance: NavigationRouteProvenance,
        distanceMeters: Double,
        expectedTravelTimeSeconds: Double,
        geometry: [NavigationCoordinate],
        steps: [NavigationRouteStepSnapshot],
        advisoryNotices: [String],
        hasHighways: Bool,
        hasTolls: Bool
    ) throws {
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw NavigationRouteContractError.invalidRouteDistance
        }
        guard expectedTravelTimeSeconds.isFinite, expectedTravelTimeSeconds >= 0 else {
            throw NavigationRouteContractError.invalidExpectedTravelTime
        }
        guard !geometry.isEmpty else {
            throw NavigationRouteContractError.emptyRouteGeometry
        }
        guard !steps.isEmpty else {
            throw NavigationRouteContractError.emptyRouteSteps
        }

        self.provenance = provenance
        self.distanceMeters = distanceMeters
        self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
        self.geometry = geometry
        self.steps = steps
        self.advisoryNotices = advisoryNotices
        self.hasHighways = hasHighways
        self.hasTolls = hasTolls
    }
}
