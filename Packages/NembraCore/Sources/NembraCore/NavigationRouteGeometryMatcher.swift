import Foundation

public enum NavigationRouteGeometryMatchingError: Error, Equatable, Sendable {
    case invalidPolicy
}

/// Confidence thresholds for converting already-screened phone location evidence
/// into route-position estimates. There is intentionally no production default;
/// real outdoor traces must justify these values.
public struct NavigationRouteGeometryMatchingPolicy: Equatable, Sendable {
    public let maximumRouteDistanceMeters: Double
    public let minimumStepAmbiguitySeparationMeters: Double

    public init(
        maximumRouteDistanceMeters: Double,
        minimumStepAmbiguitySeparationMeters: Double
    ) throws {
        guard maximumRouteDistanceMeters.isFinite,
              maximumRouteDistanceMeters > 0,
              minimumStepAmbiguitySeparationMeters.isFinite,
              minimumStepAmbiguitySeparationMeters > 0 else {
            throw NavigationRouteGeometryMatchingError.invalidPolicy
        }

        self.maximumRouteDistanceMeters = maximumRouteDistanceMeters
        self.minimumStepAmbiguitySeparationMeters = minimumStepAmbiguitySeparationMeters
    }
}

/// A navigation-only projection of quality-screened location evidence onto one
/// immutable route. Distances here are presentation/guidance estimates scaled by
/// provider route facts; they never become ride GPS distance or measured speed.
public struct NavigationRouteGeometryMatch: Equatable, Sendable {
    public let receivedAtUptimeNanoseconds: UInt64
    public let stepIndex: Int
    public let distanceFromRouteMeters: Double
    public let distanceRemainingOnStepMeters: Double
    public let distanceRemainingOnRouteMeters: Double
    public let isProgressAssignmentConfident: Bool
    public let startsNewRouteSegment: Bool

    public func guidanceObservation(
        selectionToken: NavigationGuidanceSelectionToken
    ) throws -> NavigationGuidanceProgressObservation {
        try NavigationGuidanceProgressObservation(
            selectionToken: selectionToken,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            stepIndex: stepIndex,
            distanceRemainingOnStepMeters: distanceRemainingOnStepMeters,
            distanceRemainingOnRouteMeters: distanceRemainingOnRouteMeters,
            isProgressAssignmentConfident: isProgressAssignmentConfident
        )
    }

    public func rerouteObservation() throws -> NavigationRouteDeviationObservation {
        try NavigationRouteDeviationObservation(
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            distanceFromActiveRouteMeters: distanceFromRouteMeters,
            isProgressAssignmentConfident: isProgressAssignmentConfident
        )
    }
}

/// Deterministic route-geometry matcher fed only by `QualityScreenedRideLocation`.
///
/// The matcher performs no Core Location quality screening itself. It projects
/// the accepted coordinate onto provider route/step geometry, derives provider-
/// scaled remaining-distance estimates, and fails confidence closed for route
/// distance or step-assignment ambiguity. Numeric confidence thresholds remain
/// injected so Simulator math cannot become an outdoor production claim.
public struct NavigationRouteGeometryMatcher: Sendable {
    private let policy: NavigationRouteGeometryMatchingPolicy

    public init(policy: NavigationRouteGeometryMatchingPolicy) {
        self.policy = policy
    }

    public func match(
        location: QualityScreenedRideLocation,
        route: NavigationRouteSnapshot
    ) -> NavigationRouteGeometryMatch {
        let latitude = location.sample.latitude
        let longitude = location.sample.longitude
        let routeProjection = Self.project(
            latitude: latitude,
            longitude: longitude,
            onto: route.geometry
        )

        let stepProjections = route.steps.enumerated().map { index, step in
            (index, Self.project(latitude: latitude, longitude: longitude, onto: step.geometry))
        }
        let sortedSteps = stepProjections.sorted { lhs, rhs in
            if lhs.1.distanceMeters == rhs.1.distanceMeters {
                return lhs.0 < rhs.0
            }
            return lhs.1.distanceMeters < rhs.1.distanceMeters
        }
        let bestStep = sortedSteps[0]
        let secondStepDistance = sortedSteps.count > 1 ? sortedSteps[1].1.distanceMeters : nil
        let step = route.steps[bestStep.0]

        let stepAmbiguous: Bool
        if let secondStepDistance {
            stepAmbiguous = secondStepDistance - bestStep.1.distanceMeters
                < policy.minimumStepAmbiguitySeparationMeters
        } else {
            stepAmbiguous = false
        }

        let routeProgressUsable = routeProjection.hasDirectionalExtent || route.distanceMeters == 0
        let stepProgressUsable = bestStep.1.hasDirectionalExtent || step.distanceMeters == 0
        let confident = routeProjection.distanceMeters <= policy.maximumRouteDistanceMeters
            && !stepAmbiguous
            && routeProgressUsable
            && stepProgressUsable

        return NavigationRouteGeometryMatch(
            receivedAtUptimeNanoseconds: location.sample.receivedAtUptimeNanoseconds,
            stepIndex: bestStep.0,
            distanceFromRouteMeters: routeProjection.distanceMeters,
            distanceRemainingOnStepMeters: Self.scaledRemaining(
                providerDistanceMeters: step.distanceMeters,
                progressFraction: bestStep.1.progressFraction
            ),
            distanceRemainingOnRouteMeters: Self.scaledRemaining(
                providerDistanceMeters: route.distanceMeters,
                progressFraction: routeProjection.progressFraction
            ),
            isProgressAssignmentConfident: confident,
            startsNewRouteSegment: location.startsNewRouteSegment
        )
    }

    private struct Projection {
        let distanceMeters: Double
        let progressFraction: Double
        let hasDirectionalExtent: Bool
    }

    private static func project(
        latitude: Double,
        longitude: Double,
        onto geometry: [NavigationRouteCoordinate]
    ) -> Projection {
        if geometry.count == 1 {
            return Projection(
                distanceMeters: greatCircleDistanceMeters(
                    latitude1: latitude,
                    longitude1: longitude,
                    latitude2: geometry[0].latitude,
                    longitude2: geometry[0].longitude
                ),
                progressFraction: 0,
                hasDirectionalExtent: false
            )
        }

        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(geometry.count - 1)
        var totalLength = 0.0
        for index in 0..<(geometry.count - 1) {
            let length = greatCircleDistanceMeters(
                latitude1: geometry[index].latitude,
                longitude1: geometry[index].longitude,
                latitude2: geometry[index + 1].latitude,
                longitude2: geometry[index + 1].longitude
            )
            segmentLengths.append(length)
            totalLength += length
        }

        var bestDistance = Double.infinity
        var bestDistanceAlong = 0.0
        var cumulative = 0.0

        for index in 0..<(geometry.count - 1) {
            let a = localMeters(
                latitude: geometry[index].latitude,
                longitude: geometry[index].longitude,
                originLatitude: latitude,
                originLongitude: longitude
            )
            let b = localMeters(
                latitude: geometry[index + 1].latitude,
                longitude: geometry[index + 1].longitude,
                originLatitude: latitude,
                originLongitude: longitude
            )
            let dx = b.x - a.x
            let dy = b.y - a.y
            let denominator = dx * dx + dy * dy
            let t: Double
            if denominator > 0 {
                t = min(1, max(0, -(a.x * dx + a.y * dy) / denominator))
            } else {
                t = 0
            }
            let closestX = a.x + t * dx
            let closestY = a.y + t * dy
            let distance = hypot(closestX, closestY)

            if distance < bestDistance {
                bestDistance = distance
                bestDistanceAlong = cumulative + t * segmentLengths[index]
            }
            cumulative += segmentLengths[index]
        }

        let hasDirectionalExtent = totalLength > 0
        let fraction = hasDirectionalExtent ? min(1, max(0, bestDistanceAlong / totalLength)) : 0
        return Projection(
            distanceMeters: bestDistance.isFinite ? bestDistance : 0,
            progressFraction: fraction,
            hasDirectionalExtent: hasDirectionalExtent
        )
    }

    private static func scaledRemaining(
        providerDistanceMeters: Double,
        progressFraction: Double
    ) -> Double {
        let remaining = providerDistanceMeters * (1 - min(1, max(0, progressFraction)))
        return min(providerDistanceMeters, max(0, remaining))
    }

    private static func localMeters(
        latitude: Double,
        longitude: Double,
        originLatitude: Double,
        originLongitude: Double
    ) -> (x: Double, y: Double) {
        let radius = 6_371_008.8
        let radians = Double.pi / 180
        let originLatitudeRadians = originLatitude * radians
        let deltaLatitude = (latitude - originLatitude) * radians
        var deltaLongitude = (longitude - originLongitude) * radians
        while deltaLongitude > .pi { deltaLongitude -= 2 * .pi }
        while deltaLongitude < -.pi { deltaLongitude += 2 * .pi }
        return (
            x: radius * deltaLongitude * cos(originLatitudeRadians),
            y: radius * deltaLatitude
        )
    }

    private static func greatCircleDistanceMeters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let radius = 6_371_008.8
        let radians = Double.pi / 180
        let phi1 = latitude1 * radians
        let phi2 = latitude2 * radians
        let deltaPhi = (latitude2 - latitude1) * radians
        var deltaLambda = (longitude2 - longitude1) * radians
        while deltaLambda > .pi { deltaLambda -= 2 * .pi }
        while deltaLambda < -.pi { deltaLambda += 2 * .pi }
        let sinLatitude = sin(deltaPhi / 2)
        let sinLongitude = sin(deltaLambda / 2)
        let a = sinLatitude * sinLatitude + cos(phi1) * cos(phi2) * sinLongitude * sinLongitude
        let clamped = min(1, max(0, a))
        return radius * 2 * atan2(sqrt(clamped), sqrt(1 - clamped))
    }
}
