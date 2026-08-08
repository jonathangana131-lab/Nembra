import Foundation

public enum RideHistoryObservedPeakPresentationError: Error, Equatable, Sendable {
    case invalidJoinedEvidence
}

/// Product-facing state for one completed ride's durably revalidated speed peak.
///
/// A retained accepted observation can remain useful evidence even when it does not
/// satisfy the stored quality policy strongly enough to earn user-facing observed-
/// maximum wording. Missing evidence is separate from an observed zero.
public enum RideHistoryObservedPeakPresentationState: String, Equatable, Sendable {
    /// No accepted selected-source peak exists for this completed ride.
    case observedPeakUnavailable
    /// A real accepted observation exists, but relaunch-safe quality revalidation
    /// does not permit it to be promoted to an observed maximum.
    case unqualifiedAcceptedObservation
    /// The accepted observation passed the retained quality policy and the stricter
    /// zero-selected-source-gap observed-maximum gate.
    case qualifiedObservedMaximum
}

/// Stable semantic projection for Ride Details / accessibility consumers.
///
/// This type is intentionally not Codable. Durable history stores the raw evidence
/// required to recompute qualification; it never stores this derived presentation
/// verdict. `acceptedObservedSpeedEvidenceMetersPerSecond` may be present in the
/// unqualified state because the observation itself is real. Only
/// `qualifiedObservedMaximumMetersPerSecond` may be paired with observed-maximum
/// wording.
public struct RideHistoryObservedPeakPresentation: Equatable, Sendable {
    public let sessionID: UUID
    public let state: RideHistoryObservedPeakPresentationState
    public let selectedSource: SpeedTelemetrySource

    /// Highest accepted selected-source observation retained by this ride, whether
    /// or not the complete quality policy permits observed-maximum wording.
    public let acceptedObservedSpeedEvidenceMetersPerSecond: Double?
    public let acceptedObservedSpeedAccuracyMetersPerSecond: Double?
    public let observationContinuity: PeakSpeedObservationContinuity?

    /// Present only when the durable evidence revalidates as observed-max eligible.
    public let qualifiedObservedMaximumMetersPerSecond: Double?

    /// Consumers may use confident "observed maximum" wording only when true.
    public let permitsObservedMaximumWording: Bool

    /// True when a real accepted observation is exposed but its evidence does not
    /// qualify for observed-maximum wording. UI should keep the number explicitly
    /// subordinate to its incomplete/unqualified evidence state.
    public let requiresQualityDisclosure: Bool

    fileprivate init(
        sessionID: UUID,
        state: RideHistoryObservedPeakPresentationState,
        selectedSource: SpeedTelemetrySource,
        acceptedObservedSpeedEvidenceMetersPerSecond: Double?,
        acceptedObservedSpeedAccuracyMetersPerSecond: Double?,
        observationContinuity: PeakSpeedObservationContinuity?,
        qualifiedObservedMaximumMetersPerSecond: Double?,
        permitsObservedMaximumWording: Bool,
        requiresQualityDisclosure: Bool
    ) {
        self.sessionID = sessionID
        self.state = state
        self.selectedSource = selectedSource
        self.acceptedObservedSpeedEvidenceMetersPerSecond = acceptedObservedSpeedEvidenceMetersPerSecond
        self.acceptedObservedSpeedAccuracyMetersPerSecond = acceptedObservedSpeedAccuracyMetersPerSecond
        self.observationContinuity = observationContinuity
        self.qualifiedObservedMaximumMetersPerSecond = qualifiedObservedMaximumMetersPerSecond
        self.permitsObservedMaximumWording = permitsObservedMaximumWording
        self.requiresQualityDisclosure = requiresQualityDisclosure
    }
}

public enum RideHistoryObservedPeakPresenter {
    /// Revalidates durable raw evidence every time it creates a product projection.
    ///
    /// Qualification is never read from a cached/persisted boolean. The trusted
    /// joined record has already proven the attachment belongs to the exact
    /// immutable completed ride; this layer then reruns its retained quality policy.
    public static func present(
        _ joined: RideHistoryObservedPeakJoinedRecord
    ) throws -> RideHistoryObservedPeakPresentation {
        let evidence = joined.observedPeakRecord.evidence
        guard joined.sessionID == evidence.sessionID,
              evidence.source != .motionAssist else {
            throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
        }

        let assessment: RideObservedPeakHistoryAssessment
        do {
            assessment = try joined.assessment()
        } catch {
            throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
        }

        guard assessment.isReadinessReady == assessment.failures.isEmpty else {
            throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
        }

        guard let completedPeak = evidence.completedPeak else {
            guard !assessment.isObservedMaximumEligible,
                  assessment.failures.contains(.peakUnavailable) else {
                throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
            }
            return RideHistoryObservedPeakPresentation(
                sessionID: joined.sessionID,
                state: .observedPeakUnavailable,
                selectedSource: evidence.source,
                acceptedObservedSpeedEvidenceMetersPerSecond: nil,
                acceptedObservedSpeedAccuracyMetersPerSecond: nil,
                observationContinuity: nil,
                qualifiedObservedMaximumMetersPerSecond: nil,
                permitsObservedMaximumWording: false,
                requiresQualityDisclosure: false
            )
        }

        guard completedPeak.sessionID == joined.sessionID,
              completedPeak.source == evidence.source,
              completedPeak.source != .motionAssist,
              completedPeak.metersPerSecond.isFinite,
              completedPeak.metersPerSecond >= 0 else {
            throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
        }
        if let accuracy = completedPeak.speedAccuracyMetersPerSecond {
            guard accuracy.isFinite, accuracy >= 0 else {
                throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
            }
        }

        if assessment.isObservedMaximumEligible {
            guard assessment.failures.isEmpty,
                  assessment.telemetryQuality.isQualified,
                  evidence.foreignSourceCallbackCount == 0,
                  evidence.knownSelectedSourceInterruptionCount == 0,
                  completedPeak.knownInterruptionCount == 0,
                  completedPeak.observationContinuity == .noRecordedSelectedSourceEvidenceLoss else {
                throw RideHistoryObservedPeakPresentationError.invalidJoinedEvidence
            }
            return RideHistoryObservedPeakPresentation(
                sessionID: joined.sessionID,
                state: .qualifiedObservedMaximum,
                selectedSource: evidence.source,
                acceptedObservedSpeedEvidenceMetersPerSecond: completedPeak.metersPerSecond,
                acceptedObservedSpeedAccuracyMetersPerSecond: completedPeak.speedAccuracyMetersPerSecond,
                observationContinuity: completedPeak.observationContinuity,
                qualifiedObservedMaximumMetersPerSecond: completedPeak.metersPerSecond,
                permitsObservedMaximumWording: true,
                requiresQualityDisclosure: false
            )
        }

        return RideHistoryObservedPeakPresentation(
            sessionID: joined.sessionID,
            state: .unqualifiedAcceptedObservation,
            selectedSource: evidence.source,
            acceptedObservedSpeedEvidenceMetersPerSecond: completedPeak.metersPerSecond,
            acceptedObservedSpeedAccuracyMetersPerSecond: completedPeak.speedAccuracyMetersPerSecond,
            observationContinuity: completedPeak.observationContinuity,
            qualifiedObservedMaximumMetersPerSecond: nil,
            permitsObservedMaximumWording: false,
            requiresQualityDisclosure: true
        )
    }
}
