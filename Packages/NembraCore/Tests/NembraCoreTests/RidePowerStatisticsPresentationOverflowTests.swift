import Foundation
import Testing

@testable import NembraCore

@Suite("Ride power statistics presentation overflow")
struct RidePowerStatisticsPresentationOverflowTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!

    @Test("accepted-evidence count overflow fails closed instead of trapping")
    func acceptedCountOverflowFailsClosed() {
        let malformed = RidePowerStatisticsSummary(
            period: .allTime,
            rideCount: Int.max,
            acceptedPeakPowerRideCount: Int.max,
            gapFreePeakPowerRideCount: Int.max,
            partialPeakPowerRideCount: 1,
            unavailablePeakPowerRideCount: 0,
            peakPowerAvailability: .partial,
            highestAcceptedObservedPowerWatts: 500,
            highestAcceptedObservedPowerSessionID: sessionID,
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

    @Test("total selected-ride count overflow fails closed instead of trapping")
    func totalRideCountOverflowFailsClosed() {
        let malformed = RidePowerStatisticsSummary(
            period: .allTime,
            rideCount: Int.max,
            acceptedPeakPowerRideCount: Int.max,
            gapFreePeakPowerRideCount: Int.max,
            partialPeakPowerRideCount: 0,
            unavailablePeakPowerRideCount: 1,
            peakPowerAvailability: .partial,
            highestAcceptedObservedPowerWatts: 500,
            highestAcceptedObservedPowerSessionID: sessionID,
            highestAcceptedObservedPowerContinuity: .noRecordedSelectedSourceEvidenceLoss,
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
