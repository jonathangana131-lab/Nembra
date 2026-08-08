import Foundation
import Testing

@testable import NembraCore

@Suite("Ride statistics presentation")
struct RideStatisticsPresentationTests {
    private let longestSessionID = UUID(uuidString: "C0000000-0000-0000-0000-000000000003")!

    private func summary(
        period: RideStatisticsPeriod = .week,
        rideCount: Int,
        ridingDayCount: Int,
        trustworthyDistanceRideCount: Int,
        excludedDistanceRideCount: Int,
        distanceAvailability: RideStatisticsDistanceAvailability,
        totalDistanceMeters: Double?,
        longestRideDistanceMeters: Double?,
        longestRideSessionID: UUID?,
        longestRidingDayStreakDays: Int
    ) -> RideStatisticsSummary {
        RideStatisticsSummary(
            period: period,
            rideCount: rideCount,
            ridingDayCount: ridingDayCount,
            trustworthyDistanceRideCount: trustworthyDistanceRideCount,
            excludedDistanceRideCount: excludedDistanceRideCount,
            distanceAvailability: distanceAvailability,
            totalDistanceMeters: totalDistanceMeters,
            longestRideDistanceMeters: longestRideDistanceMeters,
            longestRideSessionID: longestRideSessionID,
            longestRidingDayStreakDays: longestRidingDayStreakDays
        )
    }

    @Test("no completed rides stays distinct from unavailable distance")
    func noCompletedRides() throws {
        let presentation = try RideStatisticsPresenter.present(
            summary(
                period: .today,
                rideCount: 0,
                ridingDayCount: 0,
                trustworthyDistanceRideCount: 0,
                excludedDistanceRideCount: 0,
                distanceAvailability: .noRides,
                totalDistanceMeters: nil,
                longestRideDistanceMeters: nil,
                longestRideSessionID: nil,
                longestRidingDayStreakDays: 0
            )
        )

        #expect(presentation.period == .today)
        #expect(presentation.state == .noCompletedRides)
        #expect(presentation.knownDistanceSubtotalMeters == nil)
        #expect(presentation.longestTrustworthyRideDistanceMeters == nil)
        #expect(!presentation.permitsCompletePeriodDistanceTotalWording)
        #expect(!presentation.permitsCompletePeriodLongestRideWording)
        #expect(!presentation.requiresKnownDistanceSubtotalDisclosure)
    }

    @Test("rides with no trustworthy mileage never become fake zero distance")
    func unavailableDistance() throws {
        let presentation = try RideStatisticsPresenter.present(
            summary(
                rideCount: 3,
                ridingDayCount: 2,
                trustworthyDistanceRideCount: 0,
                excludedDistanceRideCount: 3,
                distanceAvailability: .unavailable,
                totalDistanceMeters: nil,
                longestRideDistanceMeters: nil,
                longestRideSessionID: nil,
                longestRidingDayStreakDays: 2
            )
        )

        #expect(presentation.state == .distanceUnavailable)
        #expect(presentation.rideCount == 3)
        #expect(presentation.ridingDayCount == 2)
        #expect(presentation.longestRecordedRidingDayStreakDays == 2)
        #expect(presentation.knownDistanceSubtotalMeters == nil)
        #expect(!presentation.requiresKnownDistanceSubtotalDisclosure)
    }

    @Test("partial trustworthy distance is explicitly a known subtotal")
    func partialDistanceRequiresSubtotalDisclosure() throws {
        let presentation = try RideStatisticsPresenter.present(
            summary(
                rideCount: 4,
                ridingDayCount: 3,
                trustworthyDistanceRideCount: 3,
                excludedDistanceRideCount: 1,
                distanceAvailability: .partial,
                totalDistanceMeters: 8_400,
                longestRideDistanceMeters: 3_700,
                longestRideSessionID: longestSessionID,
                longestRidingDayStreakDays: 2
            )
        )

        #expect(presentation.state == .partialTrustworthyDistance)
        #expect(presentation.ridesWithTrustworthyDistance == 3)
        #expect(presentation.ridesWithoutTrustworthyDistance == 1)
        #expect(presentation.knownDistanceSubtotalMeters == 8_400)
        #expect(presentation.longestTrustworthyRideDistanceMeters == 3_700)
        #expect(presentation.longestTrustworthyRideSessionID == longestSessionID)
        #expect(presentation.requiresKnownDistanceSubtotalDisclosure)
        #expect(!presentation.permitsCompletePeriodDistanceTotalWording)
        #expect(!presentation.permitsCompletePeriodLongestRideWording)
    }

    @Test("complete trustworthy coverage permits complete-period distance wording")
    func completeDistancePermitsCompleteWording() throws {
        let presentation = try RideStatisticsPresenter.present(
            summary(
                period: .month,
                rideCount: 3,
                ridingDayCount: 2,
                trustworthyDistanceRideCount: 3,
                excludedDistanceRideCount: 0,
                distanceAvailability: .complete,
                totalDistanceMeters: 12_600,
                longestRideDistanceMeters: 5_100,
                longestRideSessionID: longestSessionID,
                longestRidingDayStreakDays: 2
            )
        )

        #expect(presentation.period == .month)
        #expect(presentation.state == .completeTrustworthyDistance)
        #expect(presentation.knownDistanceSubtotalMeters == 12_600)
        #expect(presentation.longestTrustworthyRideDistanceMeters == 5_100)
        #expect(presentation.permitsCompletePeriodDistanceTotalWording)
        #expect(presentation.permitsCompletePeriodLongestRideWording)
        #expect(!presentation.requiresKnownDistanceSubtotalDisclosure)
    }

    @Test("a trustworthy zero-distance ride remains measured zero")
    func completeZeroDistanceRemainsZero() throws {
        let presentation = try RideStatisticsPresenter.present(
            summary(
                rideCount: 1,
                ridingDayCount: 1,
                trustworthyDistanceRideCount: 1,
                excludedDistanceRideCount: 0,
                distanceAvailability: .complete,
                totalDistanceMeters: 0,
                longestRideDistanceMeters: 0,
                longestRideSessionID: longestSessionID,
                longestRidingDayStreakDays: 1
            )
        )

        #expect(presentation.state == .completeTrustworthyDistance)
        #expect(presentation.knownDistanceSubtotalMeters == 0)
        #expect(presentation.longestTrustworthyRideDistanceMeters == 0)
        #expect(presentation.permitsCompletePeriodDistanceTotalWording)
    }

    @Test("count and availability contradictions fail closed")
    func contradictoryCountsFailClosed() {
        let malformed = summary(
            rideCount: 3,
            ridingDayCount: 2,
            trustworthyDistanceRideCount: 3,
            excludedDistanceRideCount: 0,
            distanceAvailability: .partial,
            totalDistanceMeters: 6_000,
            longestRideDistanceMeters: 3_000,
            longestRideSessionID: longestSessionID,
            longestRidingDayStreakDays: 2
        )

        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(malformed)
        }
    }

    @Test("numeric aggregate contradictions fail closed")
    func invalidNumericAggregateFailsClosed() {
        let longestExceedsSubtotal = summary(
            rideCount: 2,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: 1,
            excludedDistanceRideCount: 1,
            distanceAvailability: .partial,
            totalDistanceMeters: 1_000,
            longestRideDistanceMeters: 1_500,
            longestRideSessionID: longestSessionID,
            longestRidingDayStreakDays: 1
        )
        let nonFiniteTotal = summary(
            rideCount: 1,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: 1,
            excludedDistanceRideCount: 0,
            distanceAvailability: .complete,
            totalDistanceMeters: .infinity,
            longestRideDistanceMeters: 1_000,
            longestRideSessionID: longestSessionID,
            longestRidingDayStreakDays: 1
        )

        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(longestExceedsSubtotal)
        }
        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(nonFiniteTotal)
        }
    }

    @Test("calendar statistics contradictions fail closed independently of distance")
    func invalidCalendarStatisticsFailClosed() {
        let noRideWithRidingDay = summary(
            rideCount: 0,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: 0,
            excludedDistanceRideCount: 0,
            distanceAvailability: .noRides,
            totalDistanceMeters: nil,
            longestRideDistanceMeters: nil,
            longestRideSessionID: nil,
            longestRidingDayStreakDays: 0
        )
        let streakExceedsRidingDays = summary(
            rideCount: 2,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: 2,
            excludedDistanceRideCount: 0,
            distanceAvailability: .complete,
            totalDistanceMeters: 2_000,
            longestRideDistanceMeters: 1_100,
            longestRideSessionID: longestSessionID,
            longestRidingDayStreakDays: 2
        )

        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(noRideWithRidingDay)
        }
        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(streakExceedsRidingDays)
        }
    }

    @Test("trustworthy distance requires total longest value and winning session together")
    func distanceProvenanceShapeFailsClosed() {
        let missingWinningSession = summary(
            rideCount: 1,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: 1,
            excludedDistanceRideCount: 0,
            distanceAvailability: .complete,
            totalDistanceMeters: 1_000,
            longestRideDistanceMeters: 1_000,
            longestRideSessionID: nil,
            longestRidingDayStreakDays: 1
        )

        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(missingWinningSession)
        }
    }
}
