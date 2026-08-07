import Foundation
import Testing

@testable import NembraCore

@Suite("Ride duration cockpit clock components")
struct RideDurationCockpitClockComponentsTests {
    private let sessionID = UUID(uuidString: "E5500000-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    @Test("clock fields stay stable across minute and hour boundaries")
    func clockFieldBoundaries() {
        assertClock(nanoseconds: 0, hours: 0, minutes: 0, seconds: 0, usesHourField: false)
        assertClock(
            nanoseconds: 59_999_999_999,
            hours: 0,
            minutes: 0,
            seconds: 59,
            usesHourField: false
        )
        assertClock(
            nanoseconds: 60_000_000_000,
            hours: 0,
            minutes: 1,
            seconds: 0,
            usesHourField: false
        )
        assertClock(
            nanoseconds: 3_599_999_999_999,
            hours: 0,
            minutes: 59,
            seconds: 59,
            usesHourField: false
        )
        assertClock(
            nanoseconds: 3_600_000_000_000,
            hours: 1,
            minutes: 0,
            seconds: 0,
            usesHourField: true
        )
        assertClock(
            nanoseconds: 3_661_999_999_999,
            hours: 1,
            minutes: 1,
            seconds: 1,
            usesHourField: true
        )
    }

    @Test("subsecond evidence never rounds the display into the next second")
    func subsecondEvidenceRoundsDownOnly() {
        let value = observedValue(nanoseconds: 999_999_999)
        let components = value?.clockComponents

        #expect(value?.wholeObservedSeconds == 0)
        #expect(components?.wholeObservedSeconds == 0)
        #expect(components?.hours == 0)
        #expect(components?.minutes == 0)
        #expect(components?.seconds == 0)
    }

    @Test("maximum UInt64 duration decomposes without overflow")
    func maximumDurationIsOverflowSafe() {
        guard let value = observedValue(nanoseconds: UInt64.max) else {
            Issue.record("Expected maximum duration to remain presentable")
            return
        }

        let wholeSeconds = UInt64.max / 1_000_000_000
        let expectedWithinHour = wholeSeconds % 3_600
        let components = value.clockComponents

        #expect(components.sessionID == sessionID)
        #expect(components.role == .elapsedObserved)
        #expect(components.wholeObservedSeconds == wholeSeconds)
        #expect(components.hours == wholeSeconds / 3_600)
        #expect(components.minutes == UInt8(expectedWithinHour / 60))
        #expect(components.seconds == UInt8(expectedWithinHour % 60))
        #expect(components.usesHourField)
    }

    @Test("partial observed duration keeps its truth qualifier inside clock payload")
    func partialRoleIsNotPromoted() {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: 61_000_000_000,
            coverage: .partial,
            observationSegmentCount: 2
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: snapshot) else {
            Issue.record("Expected partial observed duration")
            return
        }

        let components = value.clockComponents
        #expect(components.sessionID == sessionID)
        #expect(components.role == .partialObserved)
        #expect(components.wholeObservedSeconds == 61)
        #expect(components.hours == 0)
        #expect(components.minutes == 1)
        #expect(components.seconds == 1)
        #expect(!components.usesHourField)
    }

    private func assertClock(
        nanoseconds: UInt64,
        hours: UInt64,
        minutes: UInt8,
        seconds: UInt8,
        usesHourField: Bool
    ) {
        guard let value = observedValue(nanoseconds: nanoseconds) else {
            Issue.record("Expected observed duration for \(nanoseconds) ns")
            return
        }

        let components = value.clockComponents
        #expect(components.sessionID == sessionID)
        #expect(components.role == .elapsedObserved)
        #expect(components.wholeObservedSeconds == nanoseconds / 1_000_000_000)
        #expect(components.hours == hours)
        #expect(components.minutes == minutes)
        #expect(components.seconds == seconds)
        #expect(components.usesHourField == usesHourField)
    }

    private func observedValue(nanoseconds: UInt64) -> RideDurationCockpitValue? {
        let snapshot = RideSessionDurationEvidenceSnapshot(
            sessionID: sessionID,
            observedDurationNanoseconds: nanoseconds,
            coverage: .complete,
            observationSegmentCount: 1
        )

        guard case let .observed(value) = RideDurationCockpitState(snapshot: snapshot) else {
            return nil
        }
        return value
    }
}
