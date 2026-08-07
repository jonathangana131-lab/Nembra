#if canImport(MapKit) && canImport(CoreLocation)
import CoreLocation
import MapKit
import NembraCore

/// Concrete factory for the server-backed Apple directions transport. Request
/// identity/race correctness remains owned by `NavigationDirectionsOperationCoordinator`;
/// this type only constructs one MapKit operation and maps platform/projection errors.
@MainActor
public final class AppleMapKitDirectionsOperationFactory: NavigationDirectionsOperationFactory {
    public init() {}

    public func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation {
        let mapKitRequest = try AppleMapKitRequestProjection.makeRequest(from: request)
        return AppleMapKitDirectionsOperation(
            directions: MKDirections(request: mapKitRequest),
            requestedTransportMode: request.transportMode
        )
    }

    public func failure(from error: Error) -> NavigationRoutePlanFailure {
        if error is AppleMapKitProjectionError || error is NavigationRouteDomainError {
            return .invalidProviderResponse
        }
        return AppleMapKitErrorProjection.failure(from: error)
    }
}

/// Thin MapKit operation wrapper. It deliberately contains no generation state:
/// a superseded/cancelled result is rejected by the provider-neutral coordinator
/// even if `MKDirections.cancel()` races a late completion.
@MainActor
final class AppleMapKitDirectionsOperation: NavigationDirectionsOperation {
    private let directions: MKDirections
    private let requestedTransportMode: NavigationRouteTransportMode

    init(
        directions: MKDirections,
        requestedTransportMode: NavigationRouteTransportMode
    ) {
        self.directions = directions
        self.requestedTransportMode = requestedTransportMode
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        let response = try await directions.calculate()
        return try response.routes.map { route in
            try AppleMapKitRouteProjection.snapshot(
                from: route,
                requestedTransportMode: requestedTransportMode
            )
        }
    }

    func cancel() {
        directions.cancel()
    }
}
#endif
