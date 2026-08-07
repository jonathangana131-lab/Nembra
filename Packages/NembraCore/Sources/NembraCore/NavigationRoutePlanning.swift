import Foundation

public enum NavigationRoutePreference: String, Equatable, Sendable {
    case any
    case avoid
}

/// A provider-neutral route request. These preferences describe what Nembra
/// asks a routing service to do; they never assert that the returned path is
/// legal or safe for an electric scooter.
public struct NavigationRoutePlanRequest: Equatable, Sendable {
    public let source: NavigationRouteCoordinate
    public let destination: NavigationRouteCoordinate
    public let transportMode: NavigationRouteTransportMode
    public let requestsAlternateRoutes: Bool
    public let highwayPreference: NavigationRoutePreference
    public let tollPreference: NavigationRoutePreference

    public init(
        source: NavigationRouteCoordinate,
        destination: NavigationRouteCoordinate,
        transportMode: NavigationRouteTransportMode,
        requestsAlternateRoutes: Bool,
        highwayPreference: NavigationRoutePreference,
        tollPreference: NavigationRoutePreference
    ) {
        self.source = source
        self.destination = destination
        self.transportMode = transportMode
        self.requestsAlternateRoutes = requestsAlternateRoutes
        self.highwayPreference = highwayPreference
        self.tollPreference = tollPreference
    }

    public static func appleMapKitCycling(
        source: NavigationRouteCoordinate,
        destination: NavigationRouteCoordinate,
        requestsAlternateRoutes: Bool = true
    ) -> NavigationRoutePlanRequest {
        NavigationRoutePlanRequest(
            source: source,
            destination: destination,
            transportMode: .cycling,
            requestsAlternateRoutes: requestsAlternateRoutes,
            highwayPreference: .any,
            tollPreference: .any
        )
    }
}

/// Provider failures projected into stable product semantics. A MapKit adapter
/// can map documented `MKError` cases into this enum without leaking MapKit into
/// NembraCore or teaching UI code to parse platform errors.
public enum NavigationRoutePlanFailure: String, Equatable, Sendable {
    case directionsUnavailable
    case loadingThrottled
    case serverFailure
    case cancelled
    case invalidProviderResponse
    case unknown
}

public enum NavigationRoutePlanningError: Error, Equatable, Sendable {
    case requestSequenceExhausted
}

/// Opaque identity for one concrete provider request generation.
///
/// `sequence` remains public for local ordering/diagnostics, but equality also
/// includes an implementation-private per-request identity. A recreated or copied
/// coordinator may legitimately mint the same sequence number; those requests must
/// never compare equal or let a stale asynchronous callback publish into a newer
/// coordinator instance.
public struct NavigationRouteRequestToken: Equatable, Sendable {
    public let sequence: UInt64
    private let identity: UUID

    fileprivate init(sequence: UInt64, identity: UUID) {
        self.sequence = sequence
        self.identity = identity
    }
}

public struct NavigationRouteRequestStart: Equatable, Sendable {
    public let token: NavigationRouteRequestToken

    /// If non-nil, the caller should cancel the provider operation associated
    /// with this prior token. Late callbacks for it are still rejected even if
    /// transport cancellation races or fails.
    public let supersededToken: NavigationRouteRequestToken?

    fileprivate init(
        token: NavigationRouteRequestToken,
        supersededToken: NavigationRouteRequestToken?
    ) {
        self.token = token
        self.supersededToken = supersededToken
    }
}

public enum NavigationRoutePlanningState: Equatable, Sendable {
    case idle
    case requesting(token: NavigationRouteRequestToken, request: NavigationRoutePlanRequest)
    case available(
        token: NavigationRouteRequestToken,
        request: NavigationRoutePlanRequest,
        routes: [NavigationRouteSnapshot]
    )
    case failed(
        token: NavigationRouteRequestToken,
        request: NavigationRoutePlanRequest,
        reason: NavigationRoutePlanFailure
    )
}

/// Deterministic request-generation state above a directions provider.
///
/// This type prevents superseded/cancelled asynchronous callbacks from
/// publishing stale routes. It deliberately does not perform network requests,
/// location screening, route progress, rerouting, or ride-distance mutation.
public struct NavigationRoutePlanningCoordinator: Sendable {
    public private(set) var state: NavigationRoutePlanningState = .idle
    private var lastSequence: UInt64

    public init() {
        lastSequence = 0
    }

    init(initialSequence: UInt64) {
        lastSequence = initialSequence
    }

    @discardableResult
    public mutating func begin(
        _ request: NavigationRoutePlanRequest
    ) throws -> NavigationRouteRequestStart {
        guard lastSequence < UInt64.max else {
            throw NavigationRoutePlanningError.requestSequenceExhausted
        }

        let supersededToken: NavigationRouteRequestToken?
        if case let .requesting(token, _) = state {
            supersededToken = token
        } else {
            supersededToken = nil
        }

        lastSequence += 1
        let token = NavigationRouteRequestToken(
            sequence: lastSequence,
            identity: UUID()
        )
        state = .requesting(token: token, request: request)
        return NavigationRouteRequestStart(
            token: token,
            supersededToken: supersededToken
        )
    }

    /// Publishes routes only when `token` is still the active request token.
    /// Empty results or route provenance that contradicts the active request's
    /// requested transport mode fail closed as an invalid provider response.
    /// Returned transport may legitimately differ and is preserved as provider truth.
    @discardableResult
    public mutating func complete(
        token: NavigationRouteRequestToken,
        routes: [NavigationRouteSnapshot]
    ) -> Bool {
        guard case let .requesting(currentToken, request) = state,
              currentToken == token else {
            return false
        }

        guard !routes.isEmpty,
              routes.allSatisfy({ $0.provenance.requestedTransportMode == request.transportMode }) else {
            state = .failed(
                token: currentToken,
                request: request,
                reason: .invalidProviderResponse
            )
            return true
        }

        state = .available(
            token: currentToken,
            request: request,
            routes: routes
        )
        return true
    }

    /// Publishes a failure only when it belongs to the active request.
    @discardableResult
    public mutating func fail(
        token: NavigationRouteRequestToken,
        reason: NavigationRoutePlanFailure
    ) -> Bool {
        guard case let .requesting(currentToken, request) = state,
              currentToken == token else {
            return false
        }

        state = .failed(
            token: currentToken,
            request: request,
            reason: reason
        )
        return true
    }

    /// Invalidates the current request generation before transport cancellation
    /// is attempted, so a racing callback can no longer publish as current.
    @discardableResult
    public mutating func cancelCurrent() -> NavigationRouteRequestToken? {
        guard case let .requesting(token, request) = state else {
            return nil
        }

        state = .failed(
            token: token,
            request: request,
            reason: .cancelled
        )
        return token
    }

    /// Clears presentation state while preserving the token of any provider
    /// request that was still active. The caller can cancel that provider work
    /// after state is already invalidated; a racing callback for the returned
    /// token is therefore rejected even if transport cancellation is delayed.
    @discardableResult
    public mutating func reset() -> NavigationRouteRequestToken? {
        let activeToken: NavigationRouteRequestToken?
        if case let .requesting(token, _) = state {
            activeToken = token
        } else {
            activeToken = nil
        }

        state = .idle
        return activeToken
    }
}
