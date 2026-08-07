import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation destination search state")
struct NavigationDestinationSearchStateTests {
    private func coordinate(_ latitude: Double = 45, _ longitude: Double = -122) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request(
        query: String = "coffee",
        resultTypes: NavigationDestinationSearchResultTypes = .all
    ) throws -> NavigationDestinationSearchRequest {
        try NavigationDestinationSearchRequest(
            query: query,
            region: nil,
            resultTypes: resultTypes
        )
    }

    private func candidate(
        title: String = "Coffee Shop",
        provider: NavigationDestinationSearchProvider = .appleMapKit
    ) throws -> NavigationDestinationSearchCandidate {
        try NavigationDestinationSearchCandidate(
            title: title,
            subtitle: "Downtown",
            coordinate: coordinate(),
            provider: provider
        )
    }

    @Test("query preserves user text and explicit result types")
    func requestPreservesIntent() throws {
        let request = try NavigationDestinationSearchRequest(
            query: "  coffee near river  ",
            region: nil,
            resultTypes: [.address, .pointOfInterest]
        )
        #expect(request.query == "  coffee near river  ")
        #expect(request.resultTypes.contains(.address))
        #expect(request.resultTypes.contains(.pointOfInterest))
        #expect(!request.resultTypes.contains(.physicalFeature))
    }

    @Test("blank queries and empty result types fail closed")
    func invalidRequestRejected() {
        #expect(throws: NavigationDestinationSearchDomainError.invalidQuery) {
            try NavigationDestinationSearchRequest(query: " \n\t ")
        }
        #expect(throws: NavigationDestinationSearchDomainError.invalidResultTypes) {
            try NavigationDestinationSearchRequest(query: "coffee", resultTypes: [])
        }
    }

    @Test("search region validates finite positive spans")
    func regionValidation() throws {
        let center = try coordinate()
        let region = try NavigationDestinationSearchRegion(
            center: center,
            latitudeDelta: 0.5,
            longitudeDelta: 1
        )
        #expect(region.center == center)
        #expect(throws: NavigationDestinationSearchDomainError.invalidRegion) {
            try NavigationDestinationSearchRegion(
                center: center,
                latitudeDelta: 0,
                longitudeDelta: 1
            )
        }
        #expect(throws: NavigationDestinationSearchDomainError.invalidRegion) {
            try NavigationDestinationSearchRegion(
                center: center,
                latitudeDelta: 1,
                longitudeDelta: .infinity
            )
        }
    }

    @Test("candidate preserves provider title subtitle and coordinate")
    func candidatePreservesFacts() throws {
        let coordinate = try coordinate(46, -123)
        let candidate = try NavigationDestinationSearchCandidate(
            title: "River Trail",
            subtitle: "Vancouver",
            coordinate: coordinate,
            provider: .appleMapKit
        )
        #expect(candidate.title == "River Trail")
        #expect(candidate.subtitle == "Vancouver")
        #expect(candidate.coordinate == coordinate)
        #expect(candidate.provider == .appleMapKit)
    }

    @Test("blank candidate title is rejected")
    func candidateTitleRequired() {
        #expect(throws: NavigationDestinationSearchDomainError.invalidQuery) {
            try NavigationDestinationSearchCandidate(
                title: "   ",
                subtitle: nil,
                coordinate: coordinate(),
                provider: .appleMapKit
            )
        }
    }

    @Test("superseding active search returns old token and rejects stale completion")
    func supersessionRejectsStaleCompletion() throws {
        var coordinator = NavigationDestinationSearchCoordinator()
        let firstRequest = try request(query: "cof")
        let secondRequest = try request(query: "coffee")
        let first = try coordinator.begin(firstRequest)
        let second = try coordinator.begin(secondRequest)

        let oldCandidate = try candidate(title: "Old")
        let currentCandidate = try candidate(title: "Current")
        let staleApplied = coordinator.complete(token: first.token, candidates: [oldCandidate])
        let currentApplied = coordinator.complete(token: second.token, candidates: [currentCandidate])

        #expect(second.supersededToken == first.token)
        #expect(!staleApplied)
        #expect(currentApplied)
        guard case let .available(token, request, candidates) = coordinator.state else {
            Issue.record("Expected available search state")
            return
        }
        #expect(token == second.token)
        #expect(request == secondRequest)
        #expect(candidates.first?.title == "Current")
    }

    @Test("empty successful search result is legitimate and distinct from provider failure")
    func emptyResultsAreAvailable() throws {
        var coordinator = NavigationDestinationSearchCoordinator()
        let request = try request(query: "unlikely exact place")
        let start = try coordinator.begin(request)
        let completed = coordinator.complete(token: start.token, candidates: [])
        #expect(completed)
        #expect(coordinator.state == .available(token: start.token, request: request, candidates: []))
    }

    @Test("current provider failure publishes exact failure reason")
    func failurePublishes() throws {
        var coordinator = NavigationDestinationSearchCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)
        let failed = coordinator.fail(token: start.token, reason: .loadingThrottled)
        #expect(failed)
        #expect(
            coordinator.state == .failed(
                token: start.token,
                request: request,
                reason: .loadingThrottled
            )
        )
    }

    @Test("cancel invalidates current search before late completion")
    func cancelWinsLateCompletion() throws {
        var coordinator = NavigationDestinationSearchCoordinator()
        let request = try request()
        let start = try coordinator.begin(request)
        let cancelledToken = coordinator.cancelCurrent()
        #expect(cancelledToken == start.token)
        #expect(
            coordinator.state == .failed(
                token: start.token,
                request: request,
                reason: .cancelled
            )
        )
        let lateCandidate = try candidate()
        let lateApplied = coordinator.complete(token: start.token, candidates: [lateCandidate])
        #expect(!lateApplied)
    }

    @Test("sequence exhaustion fails atomically")
    func sequenceExhaustionAtomic() throws {
        var coordinator = NavigationDestinationSearchCoordinator(initialSequence: .max)
        let before = coordinator.state
        #expect(throws: NavigationDestinationSearchDomainError.requestSequenceExhausted) {
            try coordinator.begin(request())
        }
        #expect(coordinator.state == before)
    }
}
