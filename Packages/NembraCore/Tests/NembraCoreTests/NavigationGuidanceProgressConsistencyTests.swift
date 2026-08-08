import Testing
@testable import NembraCore

@Suite("Navigation guidance progress consistency")
struct NavigationGuidanceProgressConsistencyTests {
    @Test("current step remaining distance cannot exceed whole route remaining distance")
    func rejectsContradictoryRemainingDistances() throws {
        let coordinate = try NavigationRouteCoordinate(latitude: 45.6380, longitude: -122.6615)
        let step = try NavigationRouteStepSnapshot(
            geometry: [coordinate],
            instructions: "Continue",
            notice: nil,
            distanceMeters: 120,
            transportMode: .cycling
        )
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Route",
            geometry: [coordinate],
            steps: [step],
            distanceMeters: 200,
            expectedTravelTimeSeconds: 90,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route)
        let before = tracker.state

        #expect(throws: NavigationGuidanceProgressError.invalidObservation) {
            _ = try NavigationGuidanceProgressObservation(
                selectionToken: token,
                receivedAtUptimeNanoseconds: 10,
                stepIndex: 0,
                distanceRemainingOnStepMeters: 80,
                distanceRemainingOnRouteMeters: 40,
                isProgressAssignmentConfident: true
            )
        }
        #expect(tracker.state == before)
    }

    @Test("equal step and route remaining distances are valid on the final step")
    func acceptsEqualRemainingDistances() throws {
        let coordinate = try NavigationRouteCoordinate(latitude: 45.6380, longitude: -122.6615)
        let step = try NavigationRouteStepSnapshot(
            geometry: [coordinate],
            instructions: "Arrive",
            notice: nil,
            distanceMeters: 80,
            transportMode: .cycling
        )
        let route = try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(),
            name: "Route",
            geometry: [coordinate],
            steps: [step],
            distanceMeters: 80,
            expectedTravelTimeSeconds: 30,
            hasHighways: false,
            hasTolls: false,
            advisoryNotices: []
        )
        var tracker = NavigationGuidanceProgressTracker()
        let token = try tracker.select(route: route)

        let observation = try NavigationGuidanceProgressObservation(
            selectionToken: token,
            receivedAtUptimeNanoseconds: 10,
            stepIndex: 0,
            distanceRemainingOnStepMeters: 25,
            distanceRemainingOnRouteMeters: 25,
            isProgressAssignmentConfident: true
        )
        #expect(try tracker.observe(observation))
    }
}
