import NembraCore

public enum NavigationDestinationSearchDomainError: Error, Equatable, Sendable {
    case invalidQuery
    case invalidResultTypes
    case invalidRegion
    case requestSequenceExhausted
}

public struct NavigationDestinationSearchResultTypes: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let address = Self(rawValue: 1 << 0)
    public static let pointOfInterest = Self(rawValue: 1 << 1)
    public static let physicalFeature = Self(rawValue: 1 << 2)
    public static let all: Self = [.address, .pointOfInterest, .physicalFeature]
}

public struct NavigationDestinationSearchRegion: Equatable, Sendable {
    public let center: NavigationRouteCoordinate
    public let latitudeDelta: Double
    public let longitudeDelta: Double

    public init(
        center: NavigationRouteCoordinate,
        latitudeDelta: Double,
        longitudeDelta: Double
    ) throws {
        guard latitudeDelta.isFinite,
              longitudeDelta.isFinite,
              latitudeDelta > 0,
              latitudeDelta <= 180,
              longitudeDelta > 0,
              longitudeDelta <= 360 else {
            throw NavigationDestinationSearchDomainError.invalidRegion
        }
        self.center = center
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

public struct NavigationDestinationSearchRequest: Equatable, Sendable {
    public let query: String
    public let region: NavigationDestinationSearchRegion?
    public let resultTypes: NavigationDestinationSearchResultTypes

    public init(
        query: String,
        region: NavigationDestinationSearchRegion? = nil,
        resultTypes: NavigationDestinationSearchResultTypes = .all
    ) throws {
        guard query.contains(where: { !$0.isWhitespace }) else {
            throw NavigationDestinationSearchDomainError.invalidQuery
        }
        guard !resultTypes.isEmpty,
              resultTypes.isSubset(of: .all) else {
            throw NavigationDestinationSearchDomainError.invalidResultTypes
        }
        self.query = query
        self.region = region
        self.resultTypes = resultTypes
    }
}

public enum NavigationDestinationSearchProvider: String, Equatable, Sendable {
    case appleMapKit
    case simulation
}

public struct NavigationDestinationSearchCandidate: Equatable, Sendable {
    public let title: String
    public let subtitle: String?
    public let coordinate: NavigationRouteCoordinate
    public let provider: NavigationDestinationSearchProvider

    public init(
        title: String,
        subtitle: String?,
        coordinate: NavigationRouteCoordinate,
        provider: NavigationDestinationSearchProvider
    ) throws {
        guard title.contains(where: { !$0.isWhitespace }) else {
            throw NavigationDestinationSearchDomainError.invalidQuery
        }
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
        self.provider = provider
    }
}

public enum NavigationDestinationSearchFailure: Equatable, Sendable {
    case unavailable
    case loadingThrottled
    case serverFailure
    case cancelled
    case invalidProviderResponse
    case unknown
}

public struct NavigationDestinationSearchToken: Equatable, Sendable {
    public let sequence: UInt64

    fileprivate init(sequence: UInt64) {
        self.sequence = sequence
    }
}

public struct NavigationDestinationSearchStart: Equatable, Sendable {
    public let token: NavigationDestinationSearchToken
    public let supersededToken: NavigationDestinationSearchToken?
}

public enum NavigationDestinationSearchState: Equatable, Sendable {
    case idle
    case requesting(
        token: NavigationDestinationSearchToken,
        request: NavigationDestinationSearchRequest
    )
    case available(
        token: NavigationDestinationSearchToken,
        request: NavigationDestinationSearchRequest,
        candidates: [NavigationDestinationSearchCandidate]
    )
    case failed(
        token: NavigationDestinationSearchToken,
        request: NavigationDestinationSearchRequest,
        reason: NavigationDestinationSearchFailure
    )
}

/// Deterministic search-request state above any provider implementation.
/// Query text remains user intent; the coordinator owns request generations so
/// a stale completion cannot replace newer suggestions/results.
public struct NavigationDestinationSearchCoordinator: Sendable {
    public private(set) var state: NavigationDestinationSearchState = .idle
    private var lastSequence: UInt64

    public init() {
        lastSequence = 0
    }

    init(initialSequence: UInt64) {
        lastSequence = initialSequence
    }

    @discardableResult
    public mutating func begin(
        _ request: NavigationDestinationSearchRequest
    ) throws -> NavigationDestinationSearchStart {
        guard lastSequence < UInt64.max else {
            throw NavigationDestinationSearchDomainError.requestSequenceExhausted
        }

        let superseded: NavigationDestinationSearchToken?
        if case let .requesting(token, _) = state {
            superseded = token
        } else {
            superseded = nil
        }

        lastSequence += 1
        let token = NavigationDestinationSearchToken(sequence: lastSequence)
        state = .requesting(token: token, request: request)
        return NavigationDestinationSearchStart(
            token: token,
            supersededToken: superseded
        )
    }

    @discardableResult
    public mutating func complete(
        token: NavigationDestinationSearchToken,
        candidates: [NavigationDestinationSearchCandidate]
    ) -> Bool {
        guard case let .requesting(currentToken, request) = state,
              currentToken == token else {
            return false
        }

        state = .available(
            token: currentToken,
            request: request,
            candidates: candidates
        )
        return true
    }

    @discardableResult
    public mutating func fail(
        token: NavigationDestinationSearchToken,
        reason: NavigationDestinationSearchFailure
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

    @discardableResult
    public mutating func cancelCurrent() -> NavigationDestinationSearchToken? {
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

    public mutating func reset() {
        state = .idle
    }
}
