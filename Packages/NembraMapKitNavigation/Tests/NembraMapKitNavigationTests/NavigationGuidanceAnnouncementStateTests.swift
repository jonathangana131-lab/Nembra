import NembraCore
import Testing
@testable import NembraMapKitNavigation

@Suite("Navigation guidance announcement state")
struct NavigationGuidanceAnnouncementStateTests {
    @Test("inactive guidance emits nothing")
    func inactiveIsSilent() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        #expect(tracker.update(.inactive) == nil)
    }

    @Test("first maneuver preserves exact provider instruction and notice")
    func firstManeuverAnnounces() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        let announcement = tracker.update(
            .active(
                routeName: "River route",
                currentInstruction: "Keep left toward River Trail",
                currentNotice: "Provider caution",
                nextInstruction: "Turn right",
                nextNotice: nil,
                distanceRemainingOnStepMeters: 80,
                distanceRemainingOnRouteMeters: 600
            )
        )

        #expect(
            announcement == .maneuver(
                routeName: "River route",
                instruction: "Keep left toward River Trail",
                notice: "Provider caution"
            )
        )
    }

    @Test("distance-only updates do not repeat a maneuver announcement")
    func distanceChangesStaySilent() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        _ = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Continue straight",
                currentNotice: nil,
                nextInstruction: "Turn right",
                nextNotice: nil,
                distanceRemainingOnStepMeters: 100,
                distanceRemainingOnRouteMeters: 500
            )
        )

        let second = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Continue straight",
                currentNotice: nil,
                nextInstruction: "Turn right",
                nextNotice: nil,
                distanceRemainingOnStepMeters: 75,
                distanceRemainingOnRouteMeters: 475
            )
        )

        #expect(second == nil)
    }

    @Test("new current instruction announces even if route name is unchanged")
    func maneuverChangeAnnounces() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        _ = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Continue straight",
                currentNotice: nil,
                nextInstruction: nil,
                nextNotice: nil,
                distanceRemainingOnStepMeters: 20,
                distanceRemainingOnRouteMeters: 200
            )
        )

        let next = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Turn right onto Pine Street",
                currentNotice: nil,
                nextInstruction: nil,
                nextNotice: nil,
                distanceRemainingOnStepMeters: 90,
                distanceRemainingOnRouteMeters: 180
            )
        )

        #expect(
            next == .maneuver(
                routeName: "Route",
                instruction: "Turn right onto Pine Street",
                notice: nil
            )
        )
    }

    @Test("notice change is meaningful and announces")
    func noticeChangeAnnounces() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        _ = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Continue",
                currentNotice: nil,
                nextInstruction: nil,
                nextNotice: nil,
                distanceRemainingOnStepMeters: 50,
                distanceRemainingOnRouteMeters: 50
            )
        )

        let changed = tracker.update(
            .active(
                routeName: "Route",
                currentInstruction: "Continue",
                currentNotice: "Use caution",
                nextInstruction: nil,
                nextNotice: nil,
                distanceRemainingOnStepMeters: 40,
                distanceRemainingOnRouteMeters: 40
            )
        )

        #expect(
            changed == .maneuver(
                routeName: "Route",
                instruction: "Continue",
                notice: "Use caution"
            )
        )
    }

    @Test("unavailable state announces once per meaningful reason")
    func unavailableReasonDeduplicates() {
        var tracker = NavigationGuidanceAnnouncementTracker()
        let first = tracker.update(
            .unavailable(routeName: "Route", reason: .continuityGap)
        )
        let repeated = tracker.update(
            .unavailable(routeName: "Route", reason: .continuityGap)
        )
        let changed = tracker.update(
            .unavailable(routeName: "Route", reason: .ambiguousProgress)
        )

        #expect(
            first == .unavailable(
                routeName: "Route",
                reason: .continuityGap
            )
        )
        #expect(repeated == nil)
        #expect(
            changed == .unavailable(
                routeName: "Route",
                reason: .ambiguousProgress
            )
        )
    }

    @Test("inactive or explicit reset allows same maneuver to announce again")
    func resetAllowsReannouncement() {
        let guidance = NavigationGuidancePresentation.active(
            routeName: "Route",
            currentInstruction: "Continue",
            currentNotice: nil,
            nextInstruction: nil,
            nextNotice: nil,
            distanceRemainingOnStepMeters: 30,
            distanceRemainingOnRouteMeters: 30
        )
        var tracker = NavigationGuidanceAnnouncementTracker()
        #expect(tracker.update(guidance) != nil)
        #expect(tracker.update(guidance) == nil)
        _ = tracker.update(.inactive)
        #expect(tracker.update(guidance) != nil)
        tracker.reset()
        #expect(tracker.update(guidance) != nil)
    }
}
