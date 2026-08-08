import Foundation
import Testing

@testable import NembraCore

@Suite("Ride statistics presentation overflow")
struct RideStatisticsPresentationOverflowTests {
    @Test("distance-evidence count overflow fails closed instead of trapping")
    func distanceEvidenceCountOverflowFailsClosed() {
        let malformed = RideStatisticsSummary(
            period: .allTime,
            rideCount: Int.max,
            ridingDayCount: 1,
            trustworthyDistanceRideCount: Int.max,
            excludedDistanceRideCount: 1,
            distanceAvailability: .partial,
            totalDistanceMeters: 1_000,
            longestRideDistanceMeters: 1_000,
            longestRideSessionID: UUID(
                uuidString: "C0000000-0000-0000-0000-000000000004"
            )!,
            longestRidingDayStreakDays: 1
        )

        #expect(throws: RideStatisticsPresentationError.invalidSummary) {
            _ = try RideStatisticsPresenter.present(malformed)
        }
    }
}
