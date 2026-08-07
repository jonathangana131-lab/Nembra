import Foundation
import Testing

@testable import NembraCore

@Suite("Ride power statistics presentation")
struct RidePowerStatisticsPresentationTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!

    private func summary(
        period: RideStatisticsPeriod = .week,
        rideCount: Int,
        accepted: Int,
        gapFree: Int,
        partial: Int,
        unavailable: Int,
        availability: RidePowerStatisticsAvailability,
        watts: Double? = nil,
        sessionID: UUID? = nil,
        continuity: PeakPowerObservationContinuity? = nil,
        modeKey: String? = nil,
        vehicleIdentityKey: String? = nil,
        identityAuthority: ObservedPowerEnvelopeScopeAuthority? = nil,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority? = nil
    ) -> RidePowerStatisticsSummary {
        RidePowerStatisticsSummary(
            period: period,
            rideCount: rideCount,
            acceptedPeakPowerRideCount: accepted,
            gapFreePeakPowerRideCount: gapFree,
            partialPeakPowerRideCount: partial,
            unavailablePeakPowerRideCount: unavailable,
            peakPowerAvailability: availability,
            highestAcceptedObservedPowerWatts: watts,
            highestAcceptedObservedPowerSessionID: sessionID,
            highestAcceptedObservedPowerContinuity: continuity,
            highestAcceptedObservedPowerConfirmedModeKey: modeKey,
            vehicleIdentityKey: vehicleIdentityKey,
            identityAuthority: identityAuthority,
            evidenceAuthority: evidenceAuthority
        )
    }

    private func simulatorSummary(
        rideCount: Int,
        accepted: Int,
        gapFree: Int,
        partial: Int,
        unavailable: Int,
        availability: RidePowerStatisticsAvailability,
        watts: Double,
        continuity: PeakPowerObservationContinuity = .noRecordedSelectedSourceEvidenceLoss,
        modeKey: String? = "drive"
    ) -> RidePowerStatisticsSummary {
        summary(
            rideCount: rideCount,
            accepted: accepted,
            gapFree: gapFree,
            partial: partial,
            unavailable: unavailable,
            availability: availability,
            watts: watts,
            sessionID: sessionID,
            continuity: continuity,
            modeKey: modeKey,
            vehicleIdentityKey: "sim-es80",
            identityAuthority: .simulatorQA,
            evidenceAuthority: .simulatorQA
        )
    }

    @Test("no rides projects no numeric value or incomplete-evidence warning")
    func noRides() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            summary(
                period: .today,
                rideCount: 0,
                accepted: 0,
                gapFree: 0,
                partial: 0,
                unavailable: 0,
                availability: .noRides
            )
        )

        #expect(presentation.period == .today)
        #expect(presentation.state == .noCompletedRides)
        #expect(presentation.rideCount == 0)
        #expect(presentation.highestAcceptedObservedPowerWatts == nil)
        #expect(!presentation.permitsCompletePeriodObservedHighWording)
        #expect(!presentation.requiresIncompleteEvidenceDisclosure)
        #expect(!presentation.isSimulatorEvidence)
    }

    @Test("completed rides without accepted power stay unavailable rather than becoming zero")
    func unavailablePower() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            summary(
                rideCount: 3,
                accepted: 0,
                gapFree: 0,
                partial: 0,
                unavailable: 3,
                availability: .unavailable
            )
        )

        #expect(presentation.state == .powerUnavailable)
        #expect(presentation.ridesWithoutAcceptedPowerEvidence == 3)
        #expect(presentation.highestAcceptedObservedPowerWatts == nil)
        #expect(!presentation.permitsCompletePeriodObservedHighWording)
        #expect(!presentation.requiresIncompleteEvidenceDisclosure)
    }

    @Test("missing rides preserve a real observed high but require partial disclosure")
    func partialMissingRideEvidence() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            simulatorSummary(
                rideCount: 3,
                accepted: 2,
                gapFree: 2,
                partial: 0,
                unavailable: 1,
                availability: .partial,
                watts: 612.5
            )
        )

        #expect(presentation.state == .partialAcceptedEvidence)
        #expect(presentation.ridesWithAcceptedPowerEvidence == 2)
        #expect(presentation.ridesWithGapFreePowerEvidence == 2)
        #expect(presentation.ridesWithoutAcceptedPowerEvidence == 1)
        #expect(presentation.highestAcceptedObservedPowerWatts == 612.5)
        #expect(presentation.highestAcceptedObservedPowerSessionID == sessionID)
        #expect(presentation.highestAcceptedObservedPowerConfirmedModeKey == "drive")
        #expect(presentation.requiresIncompleteEvidenceDisclosure)
        #expect(!presentation.permitsCompletePeriodObservedHighWording)
        #expect(presentation.isSimulatorEvidence)
    }

    @Test("known selected-source gaps keep period presentation partial even when every ride has a number")
    func partialKnownObservationGap() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            summary(
                rideCount: 2,
                accepted: 2,
                gapFree: 1,
                partial: 1,
                unavailable: 0,
                availability: .partial,
                watts: 488,
                sessionID: sessionID,
                continuity: .partialSelectedSourceEvidence,
                modeKey: "sport",
                vehicleIdentityKey: "verified-es80",
                identityAuthority: .verifiedVehicleIdentity,
                evidenceAuthority: .verifiedVehicleMeasurement
            )
        )

        #expect(presentation.state == .partialAcceptedEvidence)
        #expect(presentation.ridesWithPartialPowerEvidence == 1)
        #expect(presentation.ridesWithoutAcceptedPowerEvidence == 0)
        #expect(presentation.highestAcceptedObservedPowerContinuity == .partialSelectedSourceEvidence)
        #expect(presentation.requiresIncompleteEvidenceDisclosure)
        #expect(!presentation.isSimulatorEvidence)
    }

    @Test("complete gap-free coverage allows complete-period observed-high wording only")
    func completeEvidence() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            summary(
                period: .month,
                rideCount: 4,
                accepted: 4,
                gapFree: 4,
                partial: 0,
                unavailable: 0,
                availability: .complete,
                watts: 731,
                sessionID: sessionID,
                continuity: .noRecordedSelectedSourceEvidenceLoss,
                modeKey: "drive",
                vehicleIdentityKey: "verified-es80",
                identityAuthority: .verifiedVehicleIdentity,
                evidenceAuthority: .verifiedVehicleMeasurement
            )
        )

        #expect(presentation.period == .month)
        #expect(presentation.state == .completeAcceptedEvidence)
        #expect(presentation.permitsCompletePeriodObservedHighWording)
        #expect(!presentation.requiresIncompleteEvidenceDisclosure)
        #expect(presentation.highestAcceptedObservedPowerWatts == 731)
        #expect(!presentation.isSimulatorEvidence)
    }

    @Test("legitimate accepted zero watts remains displayable evidence")
    func zeroWattsRemainsAcceptedEvidence() throws {
        let presentation = try RidePowerStatisticsPresenter.present(
            simulatorSummary(
                rideCount: 1,
                accepted: 1,
                gapFree: 1,
                partial: 0,
                unavailable: 0,
                availability: .complete,
                watts: 0,
                modeKey: nil
            )
        )

        #expect(presentation.state == .completeAcceptedEvidence)
        #expect(presentation.highestAcceptedObservedPowerWatts == 0)
        #expect(presentation.highestAcceptedObservedPowerConfirmedModeKey == nil)
        #expect(presentation.permitsCompletePeriodObservedHighWording)
    }

    @Test("contradictory complete availability fails closed")
    func contradictoryCompleteSummaryFailsClosed() {
        let malformed = summary(
            rideCount: 2,
            accepted: 1,
            gapFree: 1,
            partial: 0,
            unavailable: 1,
            availability: .complete,
            watts: 400,
            sessionID: sessionID,
            continuity: .noRecordedSelectedSourceEvidenceLoss,
            vehicleIdentityKey: "sim-es80",
            identityAuthority: .simulatorQA,
            evidenceAuthority: .simulatorQA
        )

        #expect(throws: RidePowerStatisticsPresentationError.invalidSummary) {
            _ = try RidePowerStatisticsPresenter.present(malformed)
        }
    }

    @Test("numeric evidence without full provenance fails closed")
    func incompleteNumericProvenanceFailsClosed() {
        let malformed = summary(
            rideCount: 1,
            accepted: 1,
            gapFree: 1,
            partial: 0,
            unavailable: 0,
            availability: .complete,
            watts: 500,
            sessionID: nil,
            continuity: .noRecordedSelectedSourceEvidenceLoss,
            vehicleIdentityKey: "sim-es80",
            identityAuthority: .simulatorQA,
            evidenceAuthority: .simulatorQA
        )

        #expect(throws: RidePowerStatisticsPresentationError.invalidSummary) {
            _ = try RidePowerStatisticsPresenter.present(malformed)
        }
    }

    @Test("mixed Simulator and verified authority cannot reach presentation")
    func mixedAuthorityFailsClosed() {
        let malformed = summary(
            rideCount: 1,
            accepted: 1,
            gapFree: 1,
            partial: 0,
            unavailable: 0,
            availability: .complete,
            watts: 500,
            sessionID: sessionID,
            continuity: .noRecordedSelectedSourceEvidenceLoss,
            vehicleIdentityKey: "es80",
            identityAuthority: .verifiedVehicleIdentity,
            evidenceAuthority: .simulatorQA
        )

        #expect(throws: RidePowerStatisticsPresentationError.invalidSummary) {
            _ = try RidePowerStatisticsPresenter.present(malformed)
        }
    }

    @Test("blank winning mode provenance fails closed instead of reaching UI")
    func blankModeFailsClosed() {
        let malformed = simulatorSummary(
            rideCount: 1,
            accepted: 1,
            gapFree: 1,
            partial: 0,
            unavailable: 0,
            availability: .complete,
            watts: 500,
            modeKey: "   "
        )

        #expect(throws: RidePowerStatisticsPresentationError.invalidSummary) {
            _ = try RidePowerStatisticsPresenter.present(malformed)
        }
    }
}
