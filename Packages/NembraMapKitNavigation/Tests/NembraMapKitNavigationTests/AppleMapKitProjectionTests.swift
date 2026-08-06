#if canImport(MapKit) && canImport(CoreLocation)
import CoreLocation
import Foundation
import MapKit
import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Apple MapKit projection")
@MainActor
struct AppleMapKitProjectionTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func polyline(_ coordinates: [CLLocationCoordinate2D]) -> MKPolyline {
        coordinates.withUnsafeBufferPointer { buffer in
            MKPolyline(coordinates: buffer.baseAddress!, count: buffer.count)
        }
    }

    @Test("current MapKit request preserves cycling endpoints and preferences")
    func requestProjection() throws {
        let intent = NavigationRoutePlanRequest(
            source: try coordinate(45.638, -122.661),
            destination: try coordinate(45.642, -122.650),
            transportMode: .cycling,
            requestsAlternateRoutes: true,
            highwayPreference: .avoid,
            tollPreference: .any
        )

        let request = try AppleMapKitRequestProjection.makeRequest(from: intent)

        #expect(request.transportType == .cycling)
        #expect(request.requestsAlternateRoutes)
        #expect(request.highwayPreference == .avoid)
        #expect(request.tollPreference == .any)
        #expect(request.source?.location.coordinate.latitude == intent.source.latitude)
        #expect(request.source?.location.coordinate.longitude == intent.source.longitude)
        #expect(request.destination?.location.coordinate.latitude == intent.destination.latitude)
        #expect(request.destination?.location.coordinate.longitude == intent.destination.longitude)
    }

    @Test("unknown request transport fails closed")
    func unknownRequestTransportRejected() throws {
        let intent = NavigationRoutePlanRequest(
            source: try coordinate(45, -122),
            destination: try coordinate(46, -122),
            transportMode: .unknown,
            requestsAlternateRoutes: false,
            highwayPreference: .any,
            tollPreference: .any
        )

        #expect(throws: AppleMapKitProjectionError.unsupportedRequestTransportMode) {
            try AppleMapKitRequestProjection.makeRequest(from: intent)
        }
    }

    @Test("documented MapKit errors map into stable Nembra failures")
    func errorProjection() {
        func error(_ code: MKError.Code) -> NSError {
            NSError(domain: MKErrorDomain, code: code.rawValue)
        }

        #expect(AppleMapKitErrorProjection.failure(from: error(.directionsNotFound)) == .directionsUnavailable)
        #expect(AppleMapKitErrorProjection.failure(from: error(.placemarkNotFound)) == .directionsUnavailable)
        #expect(AppleMapKitErrorProjection.failure(from: error(.loadingThrottled)) == .loadingThrottled)
        #expect(AppleMapKitErrorProjection.failure(from: error(.serverFailure)) == .serverFailure)
        #expect(AppleMapKitErrorProjection.failure(from: error(.decodingFailed)) == .invalidProviderResponse)
        #expect(AppleMapKitErrorProjection.failure(from: error(.unknown)) == .unknown)
        #expect(AppleMapKitErrorProjection.failure(from: NSError(domain: "example", code: 1)) == .unknown)
    }

    @Test("combined or future returned transport remains unknown")
    func combinedTransportIsUnknown() {
        let combined = MKDirectionsTransportType.walking.union(.transit)
        #expect(AppleMapKitRouteProjection.coreTransport(combined) == .unknown)
    }

    @Test("polyline extraction preserves coordinate order")
    func polylineCoordinates() throws {
        let points = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 45.1, longitude: -122.1),
            CLLocationCoordinate2D(latitude: 45.2, longitude: -122.2),
        ]

        let projected = try AppleMapKitRouteProjection.coordinates(from: polyline(points))

        #expect(projected.count == 3)
        #expect(projected[0] == try coordinate(45.0, -122.0))
        #expect(projected[1] == try coordinate(45.1, -122.1))
        #expect(projected[2] == try coordinate(45.2, -122.2))
    }

    @Test("route projection preserves provider route and step facts")
    func routeProjectionFacts() throws {
        let firstGeometry = polyline([
            CLLocationCoordinate2D(latitude: 45.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 45.1, longitude: -122.0),
        ])
        let secondGeometry = polyline([
            CLLocationCoordinate2D(latitude: 45.1, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 45.2, longitude: -122.1),
        ])
        let routeGeometry = polyline([
            CLLocationCoordinate2D(latitude: 45.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 45.1, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 45.2, longitude: -122.1),
        ])

        let route = FakeRoute(
            navigationName: "Provider route",
            navigationPolyline: routeGeometry,
            navigationSteps: [
                FakeStep(
                    navigationPolyline: firstGeometry,
                    navigationInstructions: "Continue straight",
                    navigationNotice: nil,
                    navigationDistance: 100,
                    navigationTransportType: .cycling
                ),
                FakeStep(
                    navigationPolyline: secondGeometry,
                    navigationInstructions: "Turn right",
                    navigationNotice: "Use caution",
                    navigationDistance: 150,
                    navigationTransportType: .walking
                ),
            ],
            navigationDistance: 275,
            navigationExpectedTravelTime: 123,
            navigationHasHighways: false,
            navigationHasTolls: true,
            navigationAdvisoryNotices: ["Seasonal closure possible"],
            navigationTransportType: .cycling
        )

        let snapshot = try AppleMapKitRouteProjection.snapshotReading(
            route,
            requestedTransportMode: .cycling
        )

        #expect(snapshot.name == "Provider route")
        #expect(snapshot.provenance.provider == .appleMapKit)
        #expect(snapshot.provenance.requestedTransportMode == .cycling)
        #expect(snapshot.provenance.returnedTransportMode == .cycling)
        #expect(snapshot.distanceMeters == 275)
        #expect(snapshot.expectedTravelTimeSeconds == 123)
        #expect(snapshot.hasTolls)
        #expect(snapshot.advisoryNotices == ["Seasonal closure possible"])
        #expect(snapshot.steps.count == 2)
        #expect(snapshot.steps[0].instructions == "Continue straight")
        #expect(snapshot.steps[1].instructions == "Turn right")
        #expect(snapshot.steps[1].notice == "Use caution")
        #expect(snapshot.steps[1].transportMode == .walking)
        #expect(snapshot.steps[0].distanceMeters + snapshot.steps[1].distanceMeters != snapshot.distanceMeters)
    }
}

private struct FakeStep: AppleMapKitStepReading {
    let navigationPolyline: MKPolyline
    let navigationInstructions: String
    let navigationNotice: String?
    let navigationDistance: CLLocationDistance
    let navigationTransportType: MKDirectionsTransportType
}

private struct FakeRoute: AppleMapKitRouteReading {
    let navigationName: String
    let navigationPolyline: MKPolyline
    let navigationSteps: [FakeStep]
    let navigationDistance: CLLocationDistance
    let navigationExpectedTravelTime: TimeInterval
    let navigationHasHighways: Bool
    let navigationHasTolls: Bool
    let navigationAdvisoryNotices: [String]
    let navigationTransportType: MKDirectionsTransportType
}
#endif
