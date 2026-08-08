import Foundation

/// The only semantic roles a completed-ride peak may expose to product UI or accessibility.
///
/// `acceptedObservation` is deliberately not a maximum. It preserves a real accepted
/// speed observation while requiring the consumer to disclose that retained quality
/// evidence was insufficient for observed-maximum wording.
public enum RideHistoryObservedPeakConsumerRole: String, Equatable, Sendable {
    case unavailable
    case acceptedObservation
    case qualifiedObservedMaximum
}

/// Fail-closed consumer shape for Ride Details, history summaries, and accessibility.
///
/// This projection collapses the lower-level presentation's parallel optional values and
/// booleans into one mutually exclusive semantic role. A consumer therefore receives only
/// the numeric value that is legitimate for that role:
/// - `unavailable`: no numeric value;
/// - `acceptedObservation`: accepted evidence that must not be called a maximum;
/// - `qualifiedObservedMaximum`: the quality-qualified observed maximum.
///
/// The projection is derived presentation state only. It is not Codable, must not be
/// persisted as evidence, and never upgrades retained history into fresh telemetry.
public struct RideHistoryObservedPeakConsumerProjection: Equatable, Sendable {
    public let sessionID: UUID
    public let selectedSource: SpeedTelemetrySource
    public let role: RideHistoryObservedPeakConsumerRole
    public let speedMetersPerSecond: Double?

    /// True only for the subordinate accepted-observation role. Product UI and VoiceOver
    /// must make the incomplete/unqualified evidence state discoverable when this is true.
    public let requiresQualityDisclosure: Bool

    fileprivate init(
        sessionID: UUID,
        selectedSource: SpeedTelemetrySource,
        role: RideHistoryObservedPeakConsumerRole,
        speedMetersPerSecond: Double?,
        requiresQualityDisclosure: Bool
    ) {
        self.sessionID = sessionID
        self.selectedSource = selectedSource
        self.role = role
        self.speedMetersPerSecond = speedMetersPerSecond
        self.requiresQualityDisclosure = requiresQualityDisclosure
    }
}

/// Converts the module-owned history presentation into a consumer-safe semantic shape.
///
/// Returning `nil` means the supplied presentation is internally contradictory. Callers
/// should fail closed to an unavailable UI state rather than attempting to repair or infer
/// a maximum from the remaining fields.
public enum RideHistoryObservedPeakConsumerProjector {
    public static func project(
        _ presentation: RideHistoryObservedPeakPresentation
    ) -> RideHistoryObservedPeakConsumerProjection? {
        switch presentation.state {
        case .observedPeakUnavailable:
            guard presentation.acceptedObservedSpeedEvidenceMetersPerSecond == nil,
                  presentation.qualifiedObservedMaximumMetersPerSecond == nil,
                  !presentation.permitsObservedMaximumWording,
                  !presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                role: .unavailable,
                speedMetersPerSecond: nil,
                requiresQualityDisclosure: false
            )

        case .unqualifiedAcceptedObservation:
            guard let accepted = presentation.acceptedObservedSpeedEvidenceMetersPerSecond,
                  accepted.isFinite,
                  accepted >= 0,
                  presentation.qualifiedObservedMaximumMetersPerSecond == nil,
                  !presentation.permitsObservedMaximumWording,
                  presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                role: .acceptedObservation,
                speedMetersPerSecond: accepted,
                requiresQualityDisclosure: true
            )

        case .qualifiedObservedMaximum:
            guard let accepted = presentation.acceptedObservedSpeedEvidenceMetersPerSecond,
                  let qualified = presentation.qualifiedObservedMaximumMetersPerSecond,
                  accepted.isFinite,
                  qualified.isFinite,
                  accepted >= 0,
                  qualified >= 0,
                  accepted == qualified,
                  presentation.permitsObservedMaximumWording,
                  !presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                role: .qualifiedObservedMaximum,
                speedMetersPerSecond: qualified,
                requiresQualityDisclosure: false
            )
        }
    }
}
