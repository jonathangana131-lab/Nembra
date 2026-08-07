import NembraCore
import NembraMapKitNavigation

public enum NavigationSimulationDirectionsResponse: Equatable, Sendable {
    case routes([NavigationRouteSnapshot])
    case failure(NavigationRoutePlanFailure)
}

private struct NavigationSimulationDirectionsError: Error, Sendable {
    let failure: NavigationRoutePlanFailure
}

/// Deterministic, server-free provider for Simulator/QA composition.
///
/// It is intentionally a separate SwiftPM product so production MapKit transport
/// does not silently acquire fixture behavior. Responses are consumed in order;
/// no response means directions unavailable rather than invented route data.
@MainActor
public final class NavigationSimulationDirectionsOperationFactory: NavigationDirectionsOperationFactory {
    private var responses: [NavigationSimulationDirectionsResponse]
    public private(set) var receivedRequests: [NavigationRoutePlanRequest] = []

    public init(responses: [NavigationSimulationDirectionsResponse] = []) {
        self.responses = responses
    }

    public func enqueue(_ response: NavigationSimulationDirectionsResponse) {
        responses.append(response)
    }

    public func makeOperation(
        for request: NavigationRoutePlanRequest
    ) throws -> any NavigationDirectionsOperation {
        receivedRequests.append(request)
        guard !responses.isEmpty else {
            throw NavigationSimulationDirectionsError(failure: .directionsUnavailable)
        }
        let response = responses.removeFirst()
        return NavigationSimulationDirectionsOperation(response: response)
    }

    public func failure(from error: Error) -> NavigationRoutePlanFailure {
        if let error = error as? NavigationSimulationDirectionsError {
            return error.failure
        }
        return .unknown
    }
}

@MainActor
private final class NavigationSimulationDirectionsOperation: NavigationDirectionsOperation {
    private let response: NavigationSimulationDirectionsResponse
    private var isCancelled = false

    init(response: NavigationSimulationDirectionsResponse) {
        self.response = response
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        guard !isCancelled else {
            throw NavigationSimulationDirectionsError(failure: .cancelled)
        }
        switch response {
        case let .routes(routes):
            return routes
        case let .failure(failure):
            throw NavigationSimulationDirectionsError(failure: failure)
        }
    }

    func cancel() {
        isCancelled = true
    }
}
