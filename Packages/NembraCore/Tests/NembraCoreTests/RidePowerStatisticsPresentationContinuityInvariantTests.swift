import Foundation
import Testing

@testable import NembraCore

@Suite("Ride power statistics presentation continuity invariants")
struct RidePowerStatisticsPresentationContinuityInvariantTests {
    @Test("complete period cannot carry a winning peak with partial selected-source continuity")
    func completePeriodRejectsPartialWinningContinuity() {
        let malformed = RidePowerStatisticsSummary(
            period: .week,
            rideCount: 1,
            acceptedPeakPowerRideCount: 1,
            gapFreePeakPowerRideCount: 1,
            partialPeakPowerRideCount: 0,
            unavailablePeakPowerRideCount: 0,
            peakPowerAvailability: .complete,
            highestAcceptedObservedPowerWatts: 540,
            highestAcceptedObservedPowerSessionID: UUID(
                uuidString: "00000000-0000-0000-0000-00000000F003"
            )!,
            highestAcceptedObservedPowerContinuity: .partialSelectedSourceEvidence,
            highestAcceptedObservedPowerConfirmedModeKey: "drive",
            vehicleIdentityKey: "sim-es80",
            identityAuthority: .simulatorQA,
            evidenceAuthority: .simulatorQA
        )

        #expect(throws: RidePowerStatisticsPresentationError.invalidSummary) {
            _ = try RidePowerStatisticsPresenter.present(malformed)
        }
    }
}
