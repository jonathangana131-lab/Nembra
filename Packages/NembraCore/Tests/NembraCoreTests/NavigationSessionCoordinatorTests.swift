import Foundation
import Testing
@testable import NembraCore

@Suite("Navigation session coordinator")
struct NavigationSessionCoordinatorTests {
    private func coordinate(_ lat: Double, _ lon: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: lat, longitude: lon)
    }

    private func route() throws -> NavigationRouteSnapshot {
        let a = try coordinate(45.0, -122.0)
        let b = try coordinate(45.001, -122.0)
        let c = try coordinate(45.002, -122.0)
        let s1 = try NavigationRouteStepSnapshot(geometry: [a,b], instructions: "First", notice: nil, distanceMeters: 100, transportMode: .cycling)
        let s2 = try NavigationRouteStepSnapshot(geometry: [b,c], instructions: "Second", notice: nil, distanceMeters: 100, transportMode: .cycling)
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(), name: "Route", geometry: [a,b,c], steps: [s1,s2],
            distanceMeters: 200, expectedTravelTimeSeconds: 100, hasHighways: false, hasTolls: false, advisoryNotices: []
        )
    }

    private func location(lat: Double, lon: Double, uptime: UInt64, startsNewSegment: Bool = false) throws -> QualityScreenedRideLocation {
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let sample = try RideLocationSample(
            latitude: lat, longitude: lon, sourceMeasurementDate: date, receivedAtDate: date,
            receivedAtUptimeNanoseconds: uptime, horizontalAccuracyMeters: 3, isSimulatedBySoftware: true
        )
        return QualityScreenedRideLocation(sample: sample, distanceDeltaMeters: startsNewSegment ? nil : 1, startsNewRouteSegment: startsNewSegment)
    }

    private func coordinator() throws -> NavigationSessionCoordinator {
        NavigationSessionCoordinator(
            geometryPolicy: try NavigationRouteGeometryMatchingPolicy(
                maximumRouteDistanceMeters: 100,
                minimumStepAmbiguitySeparationMeters: 4,
                minimumWithinGeometryProgressSeparationMeters: 25
            ),
            reroutePolicy: try NavigationReroutePolicy(
                minimumDeviationDistanceMeters: 20,
                requiredConsecutiveAcceptedSamples: 2,
                minimumConsecutiveDeviationDurationNanoseconds: 10,
                rerouteCooldownNanoseconds: 100
            )
        )
    }

    @Test("screened location is ignored until a route is selected")
    func noRouteReturnsNil() throws {
        var session = try coordinator()
        let update = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 10))
        #expect(update == nil)
        #expect(session.guidanceState == .idle)
    }

    @Test("selected route produces active guidance from screened location")
    func onRouteProducesGuidance() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let updateValue = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 10))
        let update = try #require(updateValue)

        #expect(update.rerouteDecision == .keepCurrentRoute)
        #expect(update.geometryMatch.stepIndex == 0)
        guard case let .active(_, _, progress) = update.guidanceState else {
            Issue.record("Expected active guidance")
            return
        }
        #expect(progress.currentStep.instructions == "First")
    }

    @Test("one off-route point cannot request reroute")
    func onePointCannotReroute() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let updateValue = try session.process(location: location(lat: 45.0005, lon: -122.0004, uptime: 10))
        let update = try #require(updateValue)
        #expect(update.geometryMatch.distanceFromRouteMeters > 20)
        #expect(update.rerouteDecision == .keepCurrentRoute)
    }

    @Test("sustained confident deviation requests one reroute")
    func sustainedDeviationReroutes() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let firstValue = try session.process(location: location(lat: 45.0005, lon: -122.0004, uptime: 10))
        let first = try #require(firstValue)
        let secondValue = try session.process(location: location(lat: 45.0006, lon: -122.0004, uptime: 20))
        let second = try #require(secondValue)

        #expect(first.rerouteDecision == .keepCurrentRoute)
        #expect(second.rerouteDecision == .requestReroute)
    }

    @Test("sustained deviation beyond progress corridor still requests reroute")
    func farOffRouteStillReroutes() throws {
        var session = try coordinator()
        _ = try session.select(route: route())

        let firstValue = try session.process(
            location: location(lat: 45.0005, lon: -122.0020, uptime: 10)
        )
        let first = try #require(firstValue)
        let secondValue = try session.process(
            location: location(lat: 45.0006, lon: -122.0020, uptime: 20)
        )
        let second = try #require(secondValue)

        #expect(first.geometryMatch.distanceFromRouteMeters > 100)
        #expect(!first.geometryMatch.isProgressAssignmentConfident)
        #expect(first.geometryMatch.isDeviationAssessmentConfident)
        #expect(first.rerouteDecision == .keepCurrentRoute)
        #expect(second.rerouteDecision == .requestReroute)
    }

    @Test("known location segment gap resets accumulated deviation before same sample is processed")
    func gapResetsDeviation() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let firstValue = try session.process(location: location(lat: 45.0005, lon: -122.0004, uptime: 10))
        _ = try #require(firstValue)
        let gapValue = try session.process(location: location(lat: 45.0006, lon: -122.0004, uptime: 20, startsNewSegment: true))
        let gap = try #require(gapValue)

        #expect(gap.geometryMatch.startsNewRouteSegment)
        #expect(gap.rerouteDecision == .keepCurrentRoute)
    }

    @Test("non-monotonic callback is rejected before guidance or reroute mutation")
    func staleCallbackAtomic() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let initialValue = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 20))
        _ = try #require(initialValue)
        let before = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(lat: 45.0006, lon: -122, uptime: 19))
        }
        #expect(session.guidanceState == before)
    }

    @Test("selecting a new route does not allow a callback older than the process clock")
    func routeChangeKeepsProcessClock() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let initialValue = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 50))
        _ = try #require(initialValue)
        _ = try session.select(route: route())
        let before = session.guidanceState

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(lat: 45.0004, lon: -122, uptime: 49))
        }
        #expect(session.guidanceState == before)
    }

    @Test("ambiguous geometry cannot become active guidance or reroute evidence")
    func ambiguityFailsClosed() throws {
        let west1 = try coordinate(45.0, -122.001)
        let east1 = try coordinate(45.0, -121.999)
        let west2 = try coordinate(45.00005, -122.001)
        let east2 = try coordinate(45.00005, -121.999)
        let s1 = try NavigationRouteStepSnapshot(geometry: [west1,east1], instructions: "A", notice: nil, distanceMeters: 100, transportMode: .cycling)
        let s2 = try NavigationRouteStepSnapshot(geometry: [west2,east2], instructions: "B", notice: nil, distanceMeters: 100, transportMode: .cycling)
        let ambiguousRoute = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(), name: "Parallel", geometry: [west1,east1,east2,west2], steps: [s1,s2],
            distanceMeters: 250, expectedTravelTimeSeconds: 100, hasHighways: false, hasTolls: false, advisoryNotices: []
        )
        var session = try coordinator()
        _ = try session.select(route: ambiguousRoute)
        let updateValue = try session.process(location: location(lat: 45.000025, lon: -122, uptime: 10))
        let update = try #require(updateValue)

        #expect(!update.geometryMatch.isProgressAssignmentConfident)
        #expect(update.rerouteDecision == .keepCurrentRoute)
        guard case let .unavailable(_, _, reason) = update.guidanceState else {
            Issue.record("Expected unavailable guidance")
            return
        }
        #expect(reason == .ambiguousProgress)
    }

    @Test("self-intersecting single step fails progress closed at crossing")
    func selfIntersectingStepFailsClosed() throws {
        let nw = try coordinate(45.001, -122.001)
        let se = try coordinate(44.999, -121.999)
        let ne = try coordinate(45.001, -121.999)
        let sw = try coordinate(44.999, -122.001)
        let geometry = [nw, se, ne, sw]
        let step = try NavigationRouteStepSnapshot(
            geometry: geometry,
            instructions: "Crossing step",
            notice: nil,
            distanceMeters: 600,
            transportMode: .cycling
        )
        let crossingRoute = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Crossing",
            geometry: geometry,
            steps: [step],
            distanceMeters: 600,
            expectedTravelTimeSeconds: 200,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
        var session = try coordinator()
        _ = try session.select(route: crossingRoute)

        let approachValue = try session.process(
            location: location(lat: 45.0005, lon: -121.9995, uptime: 10)
        )
        let approach = try #require(approachValue)
        #expect(approach.geometryMatch.isProgressAssignmentConfident)

        let crossingValue = try session.process(
            location: location(lat: 45.0, lon: -122.0, uptime: 20)
        )
        let crossing = try #require(crossingValue)
        #expect(!crossing.geometryMatch.isProgressAssignmentConfident)
        guard case let .unavailable(_, _, reason) = crossing.guidanceState else {
            Issue.record("Expected ambiguous progress at self-intersection")
            return
        }
        #expect(reason == .ambiguousProgress)
    }

    @Test("clear route returns guidance to idle")
    func clearRoute() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let initialValue = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 10))
        _ = try #require(initialValue)
        session.clearRoute()
        #expect(session.guidanceState == .idle)
        #expect(try session.process(location: location(lat: 45.0006, lon: -122, uptime: 20)) == nil)
    }

    @Test("clearing route does not reset process monotonic callback truth")
    func clearKeepsClock() throws {
        var session = try coordinator()
        _ = try session.select(route: route())
        let initialValue = try session.process(location: location(lat: 45.0005, lon: -122, uptime: 30))
        _ = try #require(initialValue)
        session.clearRoute()
        _ = try session.select(route: route())

        #expect(throws: NavigationSessionCoordinatorError.nonMonotonicLocation) {
            try session.process(location: location(lat: 45.0004, lon: -122, uptime: 29))
        }
    }
}
