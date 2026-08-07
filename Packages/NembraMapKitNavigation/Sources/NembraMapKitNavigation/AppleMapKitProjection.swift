#if canImport(MapKit) && canImport(CoreLocation)
import CoreLocation
import Foundation
import MapKit
import NembraCore

public enum AppleMapKitProjectionError: Error, Equatable, Sendable {
    case unsupportedRequestTransportMode
}

/// Projects Nembra's provider-neutral route intent into current MapKit request
/// types. The adapter uses `MKMapItem(location:address:)` rather than the
/// deprecated placemark initializer/property surface.
@MainActor
public enum AppleMapKitRequestProjection {
    public static func makeRequest(
        from intent: NavigationRoutePlanRequest
    ) throws -> MKDirections.Request {
        let request = MKDirections.Request()
        request.source = mapItem(for: intent.source)
        request.destination = mapItem(for: intent.destination)
        request.transportType = try mapRequestTransport(intent.transportMode)
        request.requestsAlternateRoutes = intent.requestsAlternateRoutes
        request.highwayPreference = mapPreference(intent.highwayPreference)
        request.tollPreference = mapPreference(intent.tollPreference)
        return request
    }

    static func mapRequestTransport(
        _ mode: NavigationRouteTransportMode
    ) throws -> MKDirectionsTransportType {
        switch mode {
        case .any:
            return .any
        case .automobile:
            return .automobile
        case .cycling:
            return .cycling
        case .transit:
            return .transit
        case .walking:
            return .walking
        case .unknown:
            throw AppleMapKitProjectionError.unsupportedRequestTransportMode
        }
    }

    static func mapPreference(
        _ preference: NavigationRoutePreference
    ) -> MKDirections.RoutePreference {
        switch preference {
        case .any:
            return .any
        case .avoid:
            return .avoid
        }
    }

    private static func mapItem(
        for coordinate: NavigationRouteCoordinate
    ) -> MKMapItem {
        MKMapItem(
            location: CLLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            ),
            address: nil
        )
    }
}

/// Maps current MapKit errors into Nembra's stable product-facing route-plan
/// failure taxonomy. Unknown/future MapKit codes fail closed as `.unknown`.
public enum AppleMapKitErrorProjection {
    public static func failure(from error: Error) -> NavigationRoutePlanFailure {
        let nsError = error as NSError
        guard nsError.domain == MKErrorDomain,
              let rawCode = UInt(exactly: nsError.code),
              let code = MKError.Code(rawValue: rawCode) else {
            return .unknown
        }

        switch code {
        case .directionsNotFound, .placemarkNotFound:
            return .directionsUnavailable
        case .loadingThrottled:
            return .loadingThrottled
        case .serverFailure:
            return .serverFailure
        case .decodingFailed:
            return .invalidProviderResponse
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}

protocol AppleMapKitStepReading {
    var navigationPolyline: MKPolyline { get }
    var navigationInstructions: String { get }
    var navigationNotice: String? { get }
    var navigationDistance: CLLocationDistance { get }
    var navigationTransportType: MKDirectionsTransportType { get }
}

extension MKRoute.Step: AppleMapKitStepReading {
    var navigationPolyline: MKPolyline { polyline }
    var navigationInstructions: String { instructions }
    var navigationNotice: String? { notice }
    var navigationDistance: CLLocationDistance { distance }
    var navigationTransportType: MKDirectionsTransportType { transportType }
}

protocol AppleMapKitRouteReading {
    associatedtype NavigationStep: AppleMapKitStepReading

    var navigationName: String { get }
    var navigationPolyline: MKPolyline { get }
    var navigationSteps: [NavigationStep] { get }
    var navigationDistance: CLLocationDistance { get }
    var navigationExpectedTravelTime: TimeInterval { get }
    var navigationHasHighways: Bool { get }
    var navigationHasTolls: Bool { get }
    var navigationAdvisoryNotices: [String] { get }
    var navigationTransportType: MKDirectionsTransportType { get }
}

extension MKRoute: AppleMapKitRouteReading {
    var navigationName: String { name }
    var navigationPolyline: MKPolyline { polyline }
    var navigationSteps: [MKRoute.Step] { steps }
    var navigationDistance: CLLocationDistance { distance }
    var navigationExpectedTravelTime: TimeInterval { expectedTravelTime }
    var navigationHasHighways: Bool { hasHighways }
    var navigationHasTolls: Bool { hasTolls }
    var navigationAdvisoryNotices: [String] { advisoryNotices }
    var navigationTransportType: MKDirectionsTransportType { transportType }
}

/// Projects MapKit route facts into the immutable Nembra route domain without
/// relabeling cycling directions as scooter legality/safety.
@MainActor
public enum AppleMapKitRouteProjection {
    public static func snapshot(
        from route: MKRoute,
        requestedTransportMode: NavigationRouteTransportMode
    ) throws -> NavigationRouteSnapshot {
        try snapshotReading(
            route,
            requestedTransportMode: requestedTransportMode
        )
    }

    static func snapshotReading<Route: AppleMapKitRouteReading>(
        _ route: Route,
        requestedTransportMode: NavigationRouteTransportMode
    ) throws -> NavigationRouteSnapshot {
        let routeGeometry = try coordinates(from: route.navigationPolyline)
        let projectedSteps = try route.navigationSteps.map { step in
            try NavigationRouteStepSnapshot(
                geometry: coordinates(from: step.navigationPolyline),
                instructions: step.navigationInstructions,
                notice: step.navigationNotice,
                distanceMeters: step.navigationDistance,
                transportMode: coreTransport(step.navigationTransportType)
            )
        }

        return try NavigationRouteSnapshot(
            provenance: NavigationRouteProvenance(
                provider: .appleMapKit,
                requestedTransportMode: requestedTransportMode,
                returnedTransportMode: coreTransport(route.navigationTransportType)
            ),
            name: route.navigationName,
            geometry: routeGeometry,
            steps: projectedSteps,
            distanceMeters: route.navigationDistance,
            expectedTravelTimeSeconds: route.navigationExpectedTravelTime,
            hasHighways: route.navigationHasHighways,
            hasTolls: route.navigationHasTolls,
            advisoryNotices: route.navigationAdvisoryNotices
        )
    }

    static func coreTransport(
        _ transport: MKDirectionsTransportType
    ) -> NavigationRouteTransportMode {
        if transport == .any { return .any }
        if transport == .automobile { return .automobile }
        if transport == .cycling { return .cycling }
        if transport == .transit { return .transit }
        if transport == .walking { return .walking }
        return .unknown
    }

    static func coordinates(
        from polyline: MKPolyline
    ) throws -> [NavigationRouteCoordinate] {
        guard polyline.pointCount > 0 else {
            return []
        }

        var coordinates = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: polyline.pointCount
        )
        coordinates.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            polyline.getCoordinates(
                baseAddress,
                range: NSRange(location: 0, length: polyline.pointCount)
            )
        }

        return try coordinates.map {
            try NavigationRouteCoordinate(
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }
}
#endif
