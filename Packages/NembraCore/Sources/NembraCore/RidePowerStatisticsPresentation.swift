import Foundation

public enum RidePowerStatisticsPresentationError: Error, Equatable, Sendable {
    case invalidSummary
}

/// Product-facing disclosure state for accepted completed-ride propulsion-power statistics.
///
/// The state is intentionally stricter than a simple `Double?`. A numeric accepted observation
/// may be useful even when the selected period has incomplete evidence, but UI must not silently
/// promote that value into a complete period maximum.
public enum RidePowerStatisticsPresentationState: String, Codable, Equatable, Sendable {
    /// The selected period contains no completed rides.
    case noCompletedRides
    /// Completed rides exist, but none carries accepted propulsion-power evidence.
    case powerUnavailable
    /// A real highest accepted observation exists, but at least one selected ride has missing or
    /// interrupted selected-source evidence. The number may be shown only with incomplete-evidence
    /// disclosure; it is not the complete period's observed high.
    case partialAcceptedEvidence
    /// Every selected ride carries accepted propulsion-power evidence with no recorded selected-source
    /// evidence loss. The numeric value may be described as the highest accepted observation among
    /// the selected rides, while still never becoming a rated or perfect physical maximum.
    case completeAcceptedEvidence
}

/// Stable UI/accessibility projection of `RidePowerStatisticsSummary`.
///
/// This type carries only accepted statistics evidence and disclosure requirements. It never contains
/// render-interpolated power, throttle position, rated motor/controller power, a learned gauge ceiling,
/// or an inferred perfect continuous-time maximum.
public struct RidePowerStatisticsPresentation: Equatable, Sendable {
    public let period: RideStatisticsPeriod
    public let state: RidePowerStatisticsPresentationState

    public let rideCount: Int
    public let ridesWithAcceptedPowerEvidence: Int
    public let ridesWithGapFreePowerEvidence: Int
    public let ridesWithPartialPowerEvidence: Int
    public let ridesWithoutAcceptedPowerEvidence: Int

    /// Highest accepted observed value among the selected rides for which accepted evidence exists.
    ///
    /// This remains available in `.partialAcceptedEvidence` because the value itself is real accepted
    /// evidence. In that state callers must disclose incomplete coverage and must not label it as the
    /// complete period's maximum.
    public let highestAcceptedObservedPowerWatts: Double?
    public let highestAcceptedObservedPowerSessionID: UUID?
    public let highestAcceptedObservedPowerContinuity: PeakPowerObservationContinuity?
    public let highestAcceptedObservedPowerConfirmedModeKey: String?

    /// Exact accepted source scope shared by every included accepted peak. Nil when no numeric accepted
    /// power evidence is present.
    public let vehicleIdentityKey: String?
    public let identityAuthority: ObservedPowerEnvelopeScopeAuthority?
    public let evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority?

    /// True only when every selected ride has accepted gap-free power evidence.
    ///
    /// Even when true, consumer wording must remain "highest accepted observed power" (or equivalent),
    /// never rated power, throttle, certified maximum, or perfect physical maximum.
    public let permitsCompletePeriodObservedHighWording: Bool

    /// True whenever the selected period contains at least one ride whose accepted power evidence is
    /// missing or known to have selected-source coverage loss.
    public let requiresIncompleteEvidenceDisclosure: Bool

    /// True only for explicitly synthetic Simulator-QA evidence. Production UI can use this to keep
    /// synthetic acceptance/runtime scenarios visually or semantically distinct from physical vehicle
    /// evidence without re-deriving authority from strings or identity names.
    public let isSimulatorEvidence: Bool

    fileprivate init(
        period: RideStatisticsPeriod,
        state: RidePowerStatisticsPresentationState,
        rideCount: Int,
        ridesWithAcceptedPowerEvidence: Int,
        ridesWithGapFreePowerEvidence: Int,
        ridesWithPartialPowerEvidence: Int,
        ridesWithoutAcceptedPowerEvidence: Int,
        highestAcceptedObservedPowerWatts: Double?,
        highestAcceptedObservedPowerSessionID: UUID?,
        highestAcceptedObservedPowerContinuity: PeakPowerObservationContinuity?,
        highestAcceptedObservedPowerConfirmedModeKey: String?,
        vehicleIdentityKey: String?,
        identityAuthority: ObservedPowerEnvelopeScopeAuthority?,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority?,
        permitsCompletePeriodObservedHighWording: Bool,
        requiresIncompleteEvidenceDisclosure: Bool,
        isSimulatorEvidence: Bool
    ) {
        self.period = period
        self.state = state
        self.rideCount = rideCount
        self.ridesWithAcceptedPowerEvidence = ridesWithAcceptedPowerEvidence
        self.ridesWithGapFreePowerEvidence = ridesWithGapFreePowerEvidence
        self.ridesWithPartialPowerEvidence = ridesWithPartialPowerEvidence
        self.ridesWithoutAcceptedPowerEvidence = ridesWithoutAcceptedPowerEvidence
        self.highestAcceptedObservedPowerWatts = highestAcceptedObservedPowerWatts
        self.highestAcceptedObservedPowerSessionID = highestAcceptedObservedPowerSessionID
        self.highestAcceptedObservedPowerContinuity = highestAcceptedObservedPowerContinuity
        self.highestAcceptedObservedPowerConfirmedModeKey = highestAcceptedObservedPowerConfirmedModeKey
        self.vehicleIdentityKey = vehicleIdentityKey
        self.identityAuthority = identityAuthority
        self.evidenceAuthority = evidenceAuthority
        self.permitsCompletePeriodObservedHighWording = permitsCompletePeriodObservedHighWording
        self.requiresIncompleteEvidenceDisclosure = requiresIncompleteEvidenceDisclosure
        self.isSimulatorEvidence = isSimulatorEvidence
    }
}

public enum RidePowerStatisticsPresenter {
    /// Converts accepted ride-power statistics into a disclosure-safe product projection.
    ///
    /// The aggregator already constructs internally consistent summaries, but this boundary validates
    /// those invariants again so future persistence/adapters cannot accidentally turn malformed summary
    /// state into confident product wording.
    public static func present(
        _ summary: RidePowerStatisticsSummary
    ) throws -> RidePowerStatisticsPresentation {
        guard summary.rideCount >= 0,
              summary.acceptedPeakPowerRideCount >= 0,
              summary.gapFreePeakPowerRideCount >= 0,
              summary.partialPeakPowerRideCount >= 0,
              summary.unavailablePeakPowerRideCount >= 0 else {
            throw RidePowerStatisticsPresentationError.invalidSummary
        }

        let acceptedCount = summary.gapFreePeakPowerRideCount.addingReportingOverflow(
            summary.partialPeakPowerRideCount
        )
        let totalCount = summary.acceptedPeakPowerRideCount.addingReportingOverflow(
            summary.unavailablePeakPowerRideCount
        )
        guard !acceptedCount.overflow,
              !totalCount.overflow,
              acceptedCount.partialValue == summary.acceptedPeakPowerRideCount,
              totalCount.partialValue == summary.rideCount else {
            throw RidePowerStatisticsPresentationError.invalidSummary
        }

        let hasNumericEvidence = summary.highestAcceptedObservedPowerWatts != nil
        let hasSession = summary.highestAcceptedObservedPowerSessionID != nil
        let hasContinuity = summary.highestAcceptedObservedPowerContinuity != nil
        let hasVehicleIdentity = summary.vehicleIdentityKey != nil
        let hasIdentityAuthority = summary.identityAuthority != nil
        let hasEvidenceAuthority = summary.evidenceAuthority != nil

        guard hasNumericEvidence == hasSession,
              hasNumericEvidence == hasContinuity,
              hasNumericEvidence == hasVehicleIdentity,
              hasNumericEvidence == hasIdentityAuthority,
              hasNumericEvidence == hasEvidenceAuthority else {
            throw RidePowerStatisticsPresentationError.invalidSummary
        }

        if let watts = summary.highestAcceptedObservedPowerWatts {
            guard watts.isFinite, watts >= 0,
                  let vehicleIdentityKey = summary.vehicleIdentityKey,
                  !vehicleIdentityKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let identityAuthority = summary.identityAuthority,
                  let evidenceAuthority = summary.evidenceAuthority,
                  authorityPairIsValid(
                    identityAuthority: identityAuthority,
                    evidenceAuthority: evidenceAuthority
                  ) else {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }

            if let modeKey = summary.highestAcceptedObservedPowerConfirmedModeKey,
               modeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }
        } else if summary.highestAcceptedObservedPowerConfirmedModeKey != nil {
            // A confirmed mode is provenance of the winning accepted observation; it must not survive
            // when the numeric observation itself is absent.
            throw RidePowerStatisticsPresentationError.invalidSummary
        }

        let state: RidePowerStatisticsPresentationState
        switch summary.peakPowerAvailability {
        case .noRides:
            guard summary.rideCount == 0,
                  summary.acceptedPeakPowerRideCount == 0,
                  summary.gapFreePeakPowerRideCount == 0,
                  summary.partialPeakPowerRideCount == 0,
                  summary.unavailablePeakPowerRideCount == 0,
                  !hasNumericEvidence else {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }
            state = .noCompletedRides

        case .unavailable:
            guard summary.rideCount > 0,
                  summary.acceptedPeakPowerRideCount == 0,
                  summary.unavailablePeakPowerRideCount == summary.rideCount,
                  !hasNumericEvidence else {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }
            state = .powerUnavailable

        case .partial:
            guard summary.rideCount > 0,
                  summary.acceptedPeakPowerRideCount > 0,
                  summary.gapFreePeakPowerRideCount < summary.rideCount,
                  hasNumericEvidence else {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }
            state = .partialAcceptedEvidence

        case .complete:
            guard summary.rideCount > 0,
                  summary.acceptedPeakPowerRideCount == summary.rideCount,
                  summary.gapFreePeakPowerRideCount == summary.rideCount,
                  summary.partialPeakPowerRideCount == 0,
                  summary.unavailablePeakPowerRideCount == 0,
                  hasNumericEvidence else {
                throw RidePowerStatisticsPresentationError.invalidSummary
            }
            state = .completeAcceptedEvidence
        }

        let permitsCompleteWording = state == .completeAcceptedEvidence
        let requiresIncompleteDisclosure = state == .partialAcceptedEvidence
        let isSimulatorEvidence = summary.identityAuthority == .simulatorQA
            && summary.evidenceAuthority == .simulatorQA

        return RidePowerStatisticsPresentation(
            period: summary.period,
            state: state,
            rideCount: summary.rideCount,
            ridesWithAcceptedPowerEvidence: summary.acceptedPeakPowerRideCount,
            ridesWithGapFreePowerEvidence: summary.gapFreePeakPowerRideCount,
            ridesWithPartialPowerEvidence: summary.partialPeakPowerRideCount,
            ridesWithoutAcceptedPowerEvidence: summary.unavailablePeakPowerRideCount,
            highestAcceptedObservedPowerWatts: summary.highestAcceptedObservedPowerWatts,
            highestAcceptedObservedPowerSessionID: summary.highestAcceptedObservedPowerSessionID,
            highestAcceptedObservedPowerContinuity: summary.highestAcceptedObservedPowerContinuity,
            highestAcceptedObservedPowerConfirmedModeKey: summary.highestAcceptedObservedPowerConfirmedModeKey,
            vehicleIdentityKey: summary.vehicleIdentityKey,
            identityAuthority: summary.identityAuthority,
            evidenceAuthority: summary.evidenceAuthority,
            permitsCompletePeriodObservedHighWording: permitsCompleteWording,
            requiresIncompleteEvidenceDisclosure: requiresIncompleteDisclosure,
            isSimulatorEvidence: isSimulatorEvidence
        )
    }

    private static func authorityPairIsValid(
        identityAuthority: ObservedPowerEnvelopeScopeAuthority,
        evidenceAuthority: ObservedPowerEnvelopeEvidenceAuthority
    ) -> Bool {
        switch (identityAuthority, evidenceAuthority) {
        case (.simulatorQA, .simulatorQA),
             (.verifiedVehicleIdentity, .verifiedVehicleMeasurement):
            true
        default:
            false
        }
    }
}
