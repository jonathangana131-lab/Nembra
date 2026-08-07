import Foundation
import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation presentation state")
@MainActor
struct NavigationPresentationStateTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func request() throws -> NavigationRoutePlanRequest {
        .appleMapKitCycling(
            source: try coordinate(45, -122),
            destination: try coordinate(45.01, -122.01)
        )
    }

    private func route(
        name: String,
        instruction: String,
        notice: String? = nil,
        distance: Double = 100,
        returnedTransport: NavigationRouteTransportMode = .cycling
    ) throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.001, -122)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b],
            instructions: instruction,
            notice: notice,
            distanceMeters: distance,
            transportMode: returnedTransport
        )
        return try NavigationRouteSnapshot(
            provenance: NavigationRouteProvenance(
                provider: .appleMapKit,
                requestedTransportMode: .cycling,
                returnedTransportMode: returnedTransport
            ),
            name: name,
            geometry: [a, b],
            steps: [step],
            distanceMeters: distance,
            expectedTravelTimeSeconds: 42,
            hasHighways: false,
            hasTolls: true,
            advisoryNotices: ["Provider advisory"]
        )
    }

    private func experience(
        operations: [PresentationFakeOperation]
    ) throws -> NavigationExperienceCoordinator {
        NavigationExperienceCoordinator(
            factory: PresentationFakeFactory(operations: operations),
            geometryPolicy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 40,
                minimumStepAmbiguitySeparationMeters: 4
            ),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                rerouteCooldownNanoseconds: 100
            )
        )
    }

    private func location() throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let sample = try RideLocationSample(
            latitude: 45.0005,
            longitude: -122,
            sourceMeasurementDate: date,
            receivedAtDate: date,
            receivedAtUptimeNanoseconds: 10,
            horizontalAccuracyMeters: 3,
            isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(
            sample: sample,
            distanceDeltaMeters: 1,
            startsNewRouteSegment: false
        )
    }

    @Test("idle experience projects to no options and inactive guidance")
    func idlePresentation() throws {
        let coordinator = try experience(operations: [])
        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(presentation.planning == .idle)
        #expect(presentation.routeOptions.isEmpty)
        #expect(presentation.selectedRouteName == nil)
        #expect(presentation.guidance == .inactive)
    }

    @Test("provider alternatives preserve order facts provenance and remain unselected")
    func alternativesPreserveFacts() async throws {
        let first = try route(name: "Provider first", instruction: "Continue")
        let second = try route(
            name: "Provider second",
            instruction: "Walk connector",
            notice: "Use caution",
            distance: 80,
            returnedTransport: .walking
        )
        let coordinator = try experience(operations: [.init(.routes([first, second]))])
        _ = try await coordinator.plan(request())

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(presentation.routeOptions.count == 2)
        #expect(presentation.routeOptions[0].name == "Provider first")
        #expect(presentation.routeOptions[1].name == "Provider second")
        #expect(presentation.routeOptions[1].distanceMeters == 80)
        #expect(presentation.routeOptions[1].expectedTravelTimeSeconds == 42)
        #expect(presentation.routeOptions[1].hasTolls)
        #expect(presentation.routeOptions[1].advisoryNotices == ["Provider advisory"])
        #expect(presentation.routeOptions[1].provider == .appleMapKit)
        #expect(presentation.routeOptions[1].requestedTransportMode == .cycling)
        #expect(presentation.routeOptions[1].returnedTransportMode == .walking)
        #expect(presentation.routeOptions.allSatisfy { !$0.isSelected })
    }

    @Test("explicit route choice is the only selected presentation option")
    func selectedOptionIsExplicit() async throws {
        let first = try route(name: "First", instruction: "First instruction")
        let second = try route(name: "Second", instruction: "Second instruction")
        let coordinator = try experience(operations: [.init(.routes([first, second]))])
        _ = try await coordinator.plan(request())
        _ = try coordinator.selectRoute(index: 1)

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(!presentation.routeOptions[0].isSelected)
        #expect(presentation.routeOptions[1].isSelected)
        #expect(presentation.selectedRouteName == "Second")
    }

    @Test("guidance awaiting evidence stays explicitly unavailable")
    func awaitingEvidencePresentation() async throws {
        let route = try route(name: "Route", instruction: "Continue")
        let coordinator = try experience(operations: [.init(.routes([route]))])
        _ = try await coordinator.plan(request())
        _ = try coordinator.selectRoute(index: 0)

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(presentation.guidance == .unavailable(routeName: "Route", reason: .awaitingEvidence))
    }

    @Test("active guidance preserves exact provider instruction notice and unit-neutral distances")
    func activeGuidancePreservesProviderStrings() async throws {
        let route = try route(
            name: "Route",
            instruction: "Keep left toward River Trail",
            notice: "Provider caution"
        )
        let coordinator = try experience(operations: [.init(.routes([route]))])
        _ = try await coordinator.plan(request())
        _ = try coordinator.selectRoute(index: 0)
        _ = try coordinator.process(location: location())

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        guard case let .active(
            routeName,
            currentInstruction,
            currentNotice,
            nextInstruction,
            nextNotice,
            stepRemaining,
            routeRemaining
        ) = presentation.guidance else {
            Issue.record("Expected active presentation")
            return
        }
        #expect(routeName == "Route")
        #expect(currentInstruction == "Keep left toward River Trail")
        #expect(currentNotice == "Provider caution")
        #expect(nextInstruction == nil)
        #expect(nextNotice == nil)
        #expect(stepRemaining >= 0 && stepRemaining <= 100)
        #expect(routeRemaining >= 0 && routeRemaining <= 100)
    }

    @Test("planning failure preserves exact stable failure reason")
    func failurePresentation() async throws {
        let coordinator = try experience(operations: [.init(.error(PresentationError.provider))])
        let planRequest = try request()
        _ = try await coordinator.plan(planRequest)

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(presentation.planning == .failed(request: planRequest, reason: .serverFailure))
        #expect(presentation.routeOptions.isEmpty)
    }

    @Test("clear selected route removes selected presentation without deleting current alternatives")
    func clearSelectionPresentation() async throws {
        let route = try route(name: "Route", instruction: "Continue")
        let coordinator = try experience(operations: [.init(.routes([route]))])
        _ = try await coordinator.plan(request())
        _ = try coordinator.selectRoute(index: 0)
        coordinator.clearSelectedRoute()

        let presentation = NavigationPresentationProjector.snapshot(from: coordinator.snapshot)

        #expect(presentation.routeOptions.count == 1)
        #expect(!presentation.routeOptions[0].isSelected)
        #expect(presentation.selectedRouteName == nil)
        #expect(presentation.guidance == .inactive)
    }
}

private enum PresentationError: Error { case provider }

@MainActor
private final class PresentationFakeFactory: NavigationDirectionsOperationFactory {
    private var operations: [PresentationFakeOperation]

    init(operations: [PresentationFakeOperation]) {
        self.operations = operations
    }

    func makeOperation(for request: NavigationRoutePlanRequest) throws -> any NavigationDirectionsOperation {
        operations.removeFirst()
    }

    func failure(from error: Error) -> NavigationRoutePlanFailure {
        .serverFailure
    }
}

@MainActor
private final class PresentationFakeOperation: NavigationDirectionsOperation {
    enum Behavior {
        case routes([NavigationRouteSnapshot])
        case error(Error)
    }

    private let behavior: Behavior

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    func calculate() async throws -> [NavigationRouteSnapshot] {
        switch behavior {
        case let .routes(routes):
            return routes
        case let .error(error):
            throw error
        }
    }

    func cancel() {}
}
