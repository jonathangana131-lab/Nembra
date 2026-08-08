import Testing
@testable import NembraCore

@Suite("Ride duration statistics presentation")
struct RideDurationStatisticsPresentationTests {
    private func summary(
        period: RideStatisticsPeriod = .week,
        rideCount: Int,
        complete: Int,
        partial: Int,
        unavailable: Int,
        availability: RideDurationStatisticsAvailability,
        totalObservedDurationNanoseconds: UInt64? = nil
    ) -> RideDurationStatisticsSummary {
        RideDurationStatisticsSummary(
            period: period,
            rideCount: rideCount,
            completeCoverageRideCount: complete,
            partialCoverageRideCount: partial,
            unavailableDurationRideCount: unavailable,
            durationAvailability: availability,
            totalObservedDurationNanoseconds: totalObservedDurationNanoseconds
        )
    }

    @Test("no rides carries no fabricated duration or disclosure warning")
    func noRides() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                period: .today,
                rideCount: 0,
                complete: 0,
                partial: 0,
                unavailable: 0,
                availability: .noRides
            )
        )

        #expect(presentation.period == .today)
        #expect(presentation.state == .noCompletedRides)
        #expect(presentation.rideCount == 0)
        #expect(presentation.ridesWithObservedDuration == 0)
        #expect(presentation.totalObservedDurationNanoseconds == nil)
        #expect(!presentation.permitsCompletePeriodObservedDurationWording)
        #expect(!presentation.requiresIncompleteDurationDisclosure)
    }

    @Test("rides without monotonic evidence remain unavailable instead of becoming zero")
    func unavailableDuration() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                rideCount: 3,
                complete: 0,
                partial: 0,
                unavailable: 3,
                availability: .unavailable
            )
        )

        #expect(presentation.state == .durationUnavailable)
        #expect(presentation.ridesWithoutObservedDuration == 3)
        #expect(presentation.totalObservedDurationNanoseconds == nil)
        #expect(!presentation.permitsCompletePeriodObservedDurationWording)
        #expect(!presentation.requiresIncompleteDurationDisclosure)
    }

    @Test("missing ride duration preserves a real subtotal but requires incomplete disclosure")
    func partialMissingDuration() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                rideCount: 3,
                complete: 2,
                partial: 0,
                unavailable: 1,
                availability: .partial,
                totalObservedDurationNanoseconds: 1_800_000_000_000
            )
        )

        #expect(presentation.state == .partialObservedDuration)
        #expect(presentation.ridesWithObservedDuration == 2)
        #expect(presentation.ridesWithCompleteDurationCoverage == 2)
        #expect(presentation.ridesWithoutObservedDuration == 1)
        #expect(presentation.totalObservedDurationNanoseconds == 1_800_000_000_000)
        #expect(presentation.requiresIncompleteDurationDisclosure)
        #expect(!presentation.permitsCompletePeriodObservedDurationWording)
    }

    @Test("partial observation coverage remains a subtotal even when every ride has a duration value")
    func partialCoverageRequiresDisclosure() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                rideCount: 2,
                complete: 1,
                partial: 1,
                unavailable: 0,
                availability: .partial,
                totalObservedDurationNanoseconds: 900_000_000_000
            )
        )

        #expect(presentation.state == .partialObservedDuration)
        #expect(presentation.ridesWithObservedDuration == 2)
        #expect(presentation.ridesWithPartialDurationCoverage == 1)
        #expect(presentation.ridesWithoutObservedDuration == 0)
        #expect(presentation.requiresIncompleteDurationDisclosure)
        #expect(!presentation.permitsCompletePeriodObservedDurationWording)
    }

    @Test("complete coverage allows complete observed-duration wording without implying moving time")
    func completeObservedDuration() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                period: .month,
                rideCount: 4,
                complete: 4,
                partial: 0,
                unavailable: 0,
                availability: .complete,
                totalObservedDurationNanoseconds: 7_200_000_000_000
            )
        )

        #expect(presentation.period == .month)
        #expect(presentation.state == .completeObservedDuration)
        #expect(presentation.ridesWithObservedDuration == 4)
        #expect(presentation.permitsCompletePeriodObservedDurationWording)
        #expect(!presentation.requiresIncompleteDurationDisclosure)
        #expect(presentation.totalObservedDurationNanoseconds == 7_200_000_000_000)
    }

    @Test("legitimate observed zero remains zero rather than unavailable")
    func zeroObservedDurationRemainsEvidence() throws {
        let presentation = try RideDurationStatisticsPresenter.present(
            summary(
                rideCount: 1,
                complete: 1,
                partial: 0,
                unavailable: 0,
                availability: .complete,
                totalObservedDurationNanoseconds: 0
            )
        )

        #expect(presentation.state == .completeObservedDuration)
        #expect(presentation.totalObservedDurationNanoseconds == 0)
        #expect(presentation.permitsCompletePeriodObservedDurationWording)
    }

    @Test("observed rides without a subtotal fail closed")
    func missingSubtotalFailsClosed() {
        let malformed = summary(
            rideCount: 1,
            complete: 1,
            partial: 0,
            unavailable: 0,
            availability: .complete,
            totalObservedDurationNanoseconds: nil
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }

    @Test("subtotal without any observed ride fails closed")
    func orphanSubtotalFailsClosed() {
        let malformed = summary(
            rideCount: 1,
            complete: 0,
            partial: 0,
            unavailable: 1,
            availability: .unavailable,
            totalObservedDurationNanoseconds: 0
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }

    @Test("complete availability cannot hide partial coverage")
    func contradictoryCompleteCoverageFailsClosed() {
        let malformed = summary(
            rideCount: 2,
            complete: 1,
            partial: 1,
            unavailable: 0,
            availability: .complete,
            totalObservedDurationNanoseconds: 500
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }

    @Test("partial availability cannot describe an actually complete period")
    func contradictoryPartialAvailabilityFailsClosed() {
        let malformed = summary(
            rideCount: 2,
            complete: 2,
            partial: 0,
            unavailable: 0,
            availability: .partial,
            totalObservedDurationNanoseconds: 500
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }

    @Test("count overflow fails closed instead of trapping or wrapping product state")
    func countOverflowFailsClosed() {
        let malformed = summary(
            rideCount: Int.max,
            complete: Int.max,
            partial: 1,
            unavailable: 0,
            availability: .partial,
            totalObservedDurationNanoseconds: 1
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }

    @Test("reconciled ride-count overflow also fails closed")
    func reconciledCountOverflowFailsClosed() {
        let malformed = summary(
            rideCount: Int.max,
            complete: Int.max,
            partial: 0,
            unavailable: 1,
            availability: .partial,
            totalObservedDurationNanoseconds: 1
        )

        #expect(throws: RideDurationStatisticsPresentationError.invalidSummary) {
            _ = try RideDurationStatisticsPresenter.present(malformed)
        }
    }
}