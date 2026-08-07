public enum NavigationRouteDomainError: Error, Equatable, Sendable {
    case invalidCoordinate
    case invalidDistance
    case invalidExpectedTravelTime
    case emptyRouteGeometry
    case emptyRouteSteps
    case emptyStepGeometry
}

/// A platform-neutral route coordinate. This type represents provider route
/// geometry only; it is not accepted phone-location evidence and must never be
/// counted as ride distance merely because it lies on a rendered route.
public struct NavigationRouteCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) throws {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            throw NavigationRouteDomainError.invalidCoordinate
        }

        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A deliberately small transport taxonomy for the route facts Nembra can
/// preserve without importing MapKit into NembraCore. Future/combined provider
/// values must map to `unknown` rather than being guessed into a known mode.
public enum NavigationRouteTransportMode: String, Equatable, Sendable {
    case any
    case automobile
    case cycling
    case transit
    case walking
    case unknown
}

public enum NavigationRouteProvider: String, Equatable, Sendable {
    case appleMapKit
}

/// Describes what Nembra actually asked a provider for and what transport mode
/// the returned route reported. Neither field is a scooter-legality claim.
public struct NavigationRouteProvenance: Equatable, Sendable {
    public let provider: NavigationRouteProvider
    public let requestedTransportMode: NavigationRouteTransportMode
    public let returnedTransportMode: NavigationRouteTransportMode

    public init(
        provider: NavigationRouteProvider,
        requestedTransportMode: NavigationRouteTransportMode,
        returnedTransportMode: NavigationRouteTransportMode
    ) {
        self.provider = provider
        self.requestedTransportMode = requestedTransportMode
        self.returnedTransportMode = returnedTransportMode
    }

    /// The first production routing profile is intentionally a MapKit cycling
    /// request because Apple currently exposes no scooter/e-scooter transport
    /// type. This says only what was requested, never that the result is legal
    /// or safe for an AOVOPRO ES80.
    public static func appleMapKitCycling(
        returnedTransportMode: NavigationRouteTransportMode = .cycling
    ) -> NavigationRouteProvenance {
        NavigationRouteProvenance(
            provider: .appleMapKit,
            requestedTransportMode: .cycling,
            returnedTransportMode: returnedTransportMode
        )
    }
}

/// One immutable provider route step projected into NembraCore.
/// Instructions/notices are preserved provider strings; NembraCore does not
/// parse them to invent maneuver semantics.
public struct NavigationRouteStepSnapshot: Equatable, Sendable {
    public let geometry: [NavigationRouteCoordinate]
    public let instructions: String
    public let notice: String?
    public let distanceMeters: Double
    public let transportMode: NavigationRouteTransportMode

    public init(
        geometry: [NavigationRouteCoordinate],
        instructions: String,
        notice: String?,
        distanceMeters: Double,
        transportMode: NavigationRouteTransportMode
    ) throws {
        guard !geometry.isEmpty else {
            throw NavigationRouteDomainError.emptyStepGeometry
        }
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw NavigationRouteDomainError.invalidDistance
        }

        self.geometry = geometry
        self.instructions = instructions
        self.notice = notice
        self.distanceMeters = distanceMeters
        self.transportMode = transportMode
    }
}

/// Immutable route facts projected from a directions provider.
///
/// Route geometry, provider distance, and expected travel time are routing
/// information only. They do not become ride telemetry, recorded GPS distance,
/// measured speed, battery evidence, or proof that a segment is scooter-legal.
public struct NavigationRouteSnapshot: Equatable, Sendable {
    public let provenance: NavigationRouteProvenance
    public let name: String
    public let geometry: [NavigationRouteCoordinate]
    public let steps: [NavigationRouteStepSnapshot]
    public let distanceMeters: Double
    public let expectedTravelTimeSeconds: Double
    public let hasHighways: Bool
    public let hasTolls: Bool
    public let advisoryNotices: [String]

    public init(
        provenance: NavigationRouteProvenance,
        name: String,
        geometry: [NavigationRouteCoordinate],
        steps: [NavigationRouteStepSnapshot],
        distanceMeters: Double,
        expectedTravelTimeSeconds: Double,
        hasHighways: Bool,
        hasTolls: Bool,
        advisoryNotices: [String]
    ) throws {
        guard !geometry.isEmpty else {
            throw NavigationRouteDomainError.emptyRouteGeometry
        }
        guard !steps.isEmpty else {
            throw NavigationRouteDomainError.emptyRouteSteps
        }
        guard distanceMeters.isFinite, distanceMeters >= 0 else {
            throw NavigationRouteDomainError.invalidDistance
        }
        guard expectedTravelTimeSeconds.isFinite, expectedTravelTimeSeconds >= 0 else {
            throw NavigationRouteDomainError.invalidExpectedTravelTime
        }

        self.provenance = provenance
        self.name = name
        self.geometry = geometry
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.expectedTravelTimeSeconds = expectedTravelTimeSeconds
        self.hasHighways = hasHighways
        self.hasTolls = hasTolls
        self.advisoryNotices = advisoryNotices
    }
}
