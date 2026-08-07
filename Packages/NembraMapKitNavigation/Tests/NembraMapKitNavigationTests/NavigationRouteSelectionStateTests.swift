import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation route selection state")
struct NavigationRouteSelectionStateTests {
    private func coordinate(_ latitude: Double, _ longitude: Double) throws -> NavigationRouteCoordinate {
        try NavigationRouteCoordinate(latitude: latitude, longitude: longitude)
    }

    private func route(name: String, distance: Double) throws -> NavigationRouteSnapshot {
        let a = try coordinate(45, -122)
        let b = try coordinate(45.01, -122.01)
        let step = try NavigationRouteStepSnapshot(
            geometry: [a, b], instructions: name, notice: nil,
            distanceMeters: distance, transportMode: .cycling
        )
        return try NavigationRouteSnapshot(
            provenance: .appleMapKitCycling(), name: name,
            geometry: [a, b], steps: [step], distanceMeters: distance,
            expectedTravelTimeSeconds: distance / 4,
            hasHighways: false, hasTolls: false, advisoryNotices: []
        )
    }

    @Test("provider alternatives start explicitly unselected and preserve order")
    func startsUnselected() throws {
        let first = try route(name: "Provider first", distance: 100)
        let second = try route(name: "Provider second", distance: 90)
        let state = try NavigationRouteSelectionState(routes: [first, second])

        #expect(state.routes == [first, second])
        #expect(state.selectedIndex == nil)
        #expect(state.selectedRoute == nil)
    }

    @Test("explicit valid index selects exact provider route")
    func selectExplicitIndex() throws {
        let first = try route(name: "First", distance: 100)
        let second = try route(name: "Second", distance: 90)
        var state = try NavigationRouteSelectionState(routes: [first, second])

        try state.select(index: 1)

        #expect(state.selectedIndex == 1)
        #expect(state.selectedRoute == second)
    }

    @Test("invalid selection fails atomically")
    func invalidSelectionAtomic() throws {
        let first = try route(name: "First", distance: 100)
        var state = try NavigationRouteSelectionState(routes: [first])
        try state.select(index: 0)
        let before = state

        #expect(throws: NavigationRouteSelectionError.invalidSelectionIndex) {
            try state.select(index: 1)
        }
        #expect(state == before)
    }

    @Test("selection can be cleared without changing route result set")
    func clearSelection() throws {
        let first = try route(name: "First", distance: 100)
        var state = try NavigationRouteSelectionState(routes: [first])
        try state.select(index: 0)

        state.clearSelection()

        #expect(state.routes == [first])
        #expect(state.selectedIndex == nil)
        #expect(state.selectedRoute == nil)
    }

    @Test("new provider result set invalidates old route index selection")
    func replacementClearsSelection() throws {
        let first = try route(name: "First", distance: 100)
        let replacement = try route(name: "Replacement", distance: 80)
        var state = try NavigationRouteSelectionState(routes: [first])
        try state.select(index: 0)

        try state.replaceRoutes([replacement])

        #expect(state.routes == [replacement])
        #expect(state.selectedIndex == nil)
        #expect(state.selectedRoute == nil)
    }

    @Test("empty provider result cannot become selectable state")
    func emptyRoutesRejected() throws {
        #expect(throws: NavigationRouteSelectionError.emptyRoutes) {
            try NavigationRouteSelectionState(routes: [])
        }

        let route = try route(name: "Existing", distance: 100)
        var state = try NavigationRouteSelectionState(routes: [route])
        let before = state
        #expect(throws: NavigationRouteSelectionError.emptyRoutes) {
            try state.replaceRoutes([])
        }
        #expect(state == before)
    }
}
