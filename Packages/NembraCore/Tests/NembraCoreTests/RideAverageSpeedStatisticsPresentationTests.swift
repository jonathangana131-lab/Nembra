import Foundation
import Testing
@testable import NembraCore

@Suite("Ride average-speed statistics presentation")
struct RideAverageSpeedStatisticsPresentationTests {
    private func summary(
        availability: RideAverageSpeedStatisticsAvailability,
        rideCount: Int,
        includedRideCount: Int,
        excludedDistanceRideCount: Int = 0,
        excludedDurationRideCount: Int = 0,
        excludedZeroDurationRideCount: Int = 0,
        excludedMultipleEvidenceRideCount: Int = 0,
        average: Double? = nil,
        distance: Double? = nil,
        duration: UInt64? = nil
    ) -> RideAverageSpeedStatisticsSummary {
        RideAverageSpeedStatisticsSummary(
            period: .week,
            rideCount: rideCount,
            includedRideCount: includedRideCount,
            excludedDistanceRideCount: excludedDistanceRideCount,
            excludedDurationRideCount: excludedDurationRideCount,
            excludedZeroDurationRideCount: excludedZeroDurationRideCount,
            excludedMultipleEvidenceRideCount: excludedMultipleEvidenceRideCount,
            availability: availability,
            averageElapsedRideSpeedMetersPerSecond: average,
            supportingDistanceMeters: distance,
            supportingObservedDurationNanoseconds: duration
        )
    }

    @Test("no rides stays distinct from unavailable evidence")
    func noRides() throws {
        let presentation = try RideAverageSpeedStatisticsPresenter.present(
            summary(availability: .noRides, rideCount: 0, includedRideCount: 0)
        )

        #expect(presentation.state == .noCompletedRides)
        #expect(presentation.averageElapsedRideSpeedMetersPerSecond == nil)
        #expect(!presentation.permitsCompletePeriodAverageWording)
        #expect(!presentation.requiresIncompleteEvidenceDisclosure)
    }

    @Test("unavailable paired evidence never becomes fake zero speed")
    func unavailable() throws {
        let presentation = try RideAverageSpeedStatisticsPresenter.present(
            summary(
                availability: .unavailable,
                rideCount: 2,
                includedRideCount: 0,
                excludedDistanceRideCount: 1,
                excludedDurationRideCount: 1
            )
        )

        #expect(presentation.state == .averageUnavailable)
        #expect(presentation.averageElapsedRideSpeedMetersPerSecond == nil)
        #expect(presentation.supportingDistanceMeters == nil)
        #expect(presentation.supportingObservedDurationNanoseconds == nil)
    }

    @Test("partial real average remains visible only with incomplete-evidence disclosure")
    func partial() throws {
        let presentation = try RideAverageSpeedStatisticsPresenter.present(
            summary(
                availability: .partial,
                rideCount: 3,
                includedRideCount: 2,
                excludedMultipleEvidenceRideCount: 1,
                average: 4,
                distance: 2_400,
                duration: 600_000_000_000
            )
        )

        #expect(presentation.state == .partialPairedEvidence)
        #expect(presentation.ridesSupportingAverage == 2)
        #expect(presentation.averageElapsedRideSpeedMetersPerSecond == 4)
        #expect(!presentation.permitsCompletePeriodAverageWording)
        #expect(presentation.requiresIncompleteEvidenceDisclosure)
    }

    @Test("complete paired evidence permits complete-period elapsed-average wording")
    func complete() throws {
        let presentation = try RideAverageSpeedStatisticsPresenter.present(
            summary(
                availability: .complete,
                rideCount: 2,
                includedRideCount: 2,
                average: 2,
                distance: 2_000,
                duration: 1_000_000_000_000
            )
        )

        #expect(presentation.state == .completePairedEvidence)
        #expect(presentation.averageElapsedRideSpeedMetersPerSecond == 2)
        #expect(presentation.permitsCompletePeriodAverageWording)
        #expect(!presentation.requiresIncompleteEvidenceDisclosure)
    }

    @Test("legitimate zero distance over positive observed time stays real zero speed")
    func zeroSpeed() throws {
        let presentation = try RideAverageSpeedStatisticsPresenter.present(
            summary(
                availability: .complete,
                rideCount: 1,
                includedRideCount: 1,
                average: 0,
                distance: 0,
                duration: 10_000_000_000
            )
        )

        #expect(presentation.averageElapsedRideSpeedMetersPerSecond == 0)
        #expect(presentation.supportingDistanceMeters == 0)
    }

    @Test("count contradictions fail closed")
    func countContradiction() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .partial,
                    rideCount: 3,
                    includedRideCount: 1,
                    excludedDistanceRideCount: 1,
                    average: 1,
                    distance: 1,
                    duration: 1_000_000_000
                )
            )
        }
    }

    @Test("count reconciliation overflow fails closed instead of trapping")
    func countOverflow() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .unavailable,
                    rideCount: Int.max,
                    includedRideCount: 0,
                    excludedDistanceRideCount: Int.max,
                    excludedDurationRideCount: 1
                )
            )
        }
    }

    @Test("numeric support fields are all-or-nothing")
    func numericSupportShape() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 1,
                    includedRideCount: 1,
                    average: 3,
                    distance: 3,
                    duration: nil
                )
            )
        }
    }

    @Test("average must reconcile exactly with its supporting distance and duration")
    func averageReconciliation() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 1,
                    includedRideCount: 1,
                    average: 9,
                    distance: 2_000,
                    duration: 1_000_000_000_000
                )
            )
        }
    }

    @Test("zero supporting duration cannot produce a numeric average")
    func zeroSupportingDuration() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 1,
                    includedRideCount: 1,
                    average: 0,
                    distance: 0,
                    duration: 0
                )
            )
        }
    }

    @Test("non-finite or negative numeric evidence fails closed")
    func invalidNumericEvidence() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 1,
                    includedRideCount: 1,
                    average: .nan,
                    distance: 1,
                    duration: 1_000_000_000
                )
            )
        }

        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 1,
                    includedRideCount: 1,
                    average: -1,
                    distance: -1,
                    duration: 1_000_000_000
                )
            )
        }
    }

    @Test("availability contradictions fail closed")
    func availabilityContradiction() throws {
        #expect(throws: RideAverageSpeedStatisticsPresentationError.invalidSummary) {
            _ = try RideAverageSpeedStatisticsPresenter.present(
                summary(
                    availability: .complete,
                    rideCount: 2,
                    includedRideCount: 1,
                    excludedDurationRideCount: 1,
                    average: 1,
                    distance: 1,
                    duration: 1_000_000_000
                )
            )
        }
    }
}
