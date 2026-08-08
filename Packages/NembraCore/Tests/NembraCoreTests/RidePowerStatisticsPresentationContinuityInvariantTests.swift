import Foundation
import Testing

@testable import NembraCore

@Suite("Ride power statistics presentation continuity invariants")
struct RidePowerStatisticsPresentationContinuityInvariantTests {
    private let sessionID = UUID(
        uuidString: "00000000-0000-0000-0000-00000000F003"
    )!

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

    @Test("partial winner requires at least one partial-evidence ride")
    func partialWinnerRequiresPartialRideCount() {
        let malformed = RidePowerStatisticsSummary(
            period: .week,
            rideCount: 2,
            acceptedPeakPowerRideCount: 1,
            gapFreePeakPowerRideCount: 1,
            partialPeakPowerRideCount: 0,
            unavailablePeakPowerRideCount: 1,
            peakPowerAvailability: .partial,
            highestAcceptedObservedPowerWatts: 540,
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

    @Test("gap-free winner requires at least one gap-free-evidence ride")
    func gapFreeWinnerRequiresGapFreeRideCount() {
        let malformed = RidePowerStatisticsSummary(
            period: .week,
            rideCount: 2,
            acceptedPeakPowerRideCount: 1,
            gapFreePeakPowerRideCount: 0,
            partialPeakPowerRideCount: 1,
            unavailablePeakPowerRideCount: 1,
            peakPowerAvailability: .partial,
            highestAcceptedObservedPowerWatts: 540,
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
