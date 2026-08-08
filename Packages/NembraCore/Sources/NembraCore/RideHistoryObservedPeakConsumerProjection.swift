import Foundation

/// The complete product-facing meaning of one completed ride's peak-speed presentation.
///
/// Associated values make contradictory combinations unrepresentable: unavailable has no
/// number, an accepted observation carries a real subordinate value that must not be called
/// a maximum, and only the qualified case carries observed-maximum wording authority.
public enum RideHistoryObservedPeakConsumerState: Equatable, Sendable {
    case unavailable
    case acceptedObservation(metersPerSecond: Double)
    case qualifiedObservedMaximum(metersPerSecond: Double)

    /// Numeric value legitimate for this exact semantic state. This is nil only when the
    /// completed ride has no accepted selected-source peak evidence.
    public var speedMetersPerSecond: Double? {
        switch self {
        case .unavailable:
            return nil
        case .acceptedObservation(let metersPerSecond),
             .qualifiedObservedMaximum(let metersPerSecond):
            return metersPerSecond
        }
    }

    /// Product UI and VoiceOver must disclose incomplete/unqualified evidence only for the
    /// subordinate accepted-observation state.
    public var requiresQualityDisclosure: Bool {
        if case .acceptedObservation = self {
            return true
        }
        return false
    }

    /// The sole consumer-level wording authority for an observed maximum.
    public var permitsObservedMaximumWording: Bool {
        if case .qualifiedObservedMaximum = self {
            return true
        }
        return false
    }
}

/// Fail-closed consumer shape for Ride Details, history summaries, and accessibility.
///
/// This is derived presentation state only. It is intentionally not Codable, must not be
/// persisted as evidence, and never upgrades retained history into fresh telemetry.
public struct RideHistoryObservedPeakConsumerProjection: Equatable, Sendable {
    public let sessionID: UUID
    public let selectedSource: SpeedTelemetrySource
    public let state: RideHistoryObservedPeakConsumerState

    fileprivate init(
        sessionID: UUID,
        selectedSource: SpeedTelemetrySource,
        state: RideHistoryObservedPeakConsumerState
    ) {
        self.sessionID = sessionID
        self.selectedSource = selectedSource
        self.state = state
    }
}

/// Converts the module-owned durable-history presentation into an exhaustive consumer state.
///
/// Returning `nil` means the supplied presentation is internally contradictory. Callers
/// should fail closed to unavailable UI rather than repair optionals, infer a maximum, or
/// reinterpret incomplete evidence. The sealed presentation is revalidated here so this
/// boundary remains safe if its lower-level representation evolves later.
public enum RideHistoryObservedPeakConsumerProjector {
    public static func project(
        _ presentation: RideHistoryObservedPeakPresentation
    ) -> RideHistoryObservedPeakConsumerProjection? {
        if case .motionAssist = presentation.selectedSource {
            return nil
        }

        switch presentation.state {
        case .observedPeakUnavailable:
            guard presentation.acceptedObservedSpeedEvidenceMetersPerSecond == nil,
                  presentation.acceptedObservedSpeedAccuracyMetersPerSecond == nil,
                  presentation.observationContinuity == nil,
                  presentation.qualifiedObservedMaximumMetersPerSecond == nil,
                  !presentation.permitsObservedMaximumWording,
                  !presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                state: .unavailable
            )

        case .unqualifiedAcceptedObservation:
            guard let accepted = presentation.acceptedObservedSpeedEvidenceMetersPerSecond,
                  accepted.isFinite,
                  accepted >= 0,
                  validAccuracy(presentation.acceptedObservedSpeedAccuracyMetersPerSecond),
                  presentation.observationContinuity != nil,
                  presentation.qualifiedObservedMaximumMetersPerSecond == nil,
                  !presentation.permitsObservedMaximumWording,
                  presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                state: .acceptedObservation(metersPerSecond: accepted)
            )

        case .qualifiedObservedMaximum:
            guard let accepted = presentation.acceptedObservedSpeedEvidenceMetersPerSecond,
                  let qualified = presentation.qualifiedObservedMaximumMetersPerSecond,
                  accepted.isFinite,
                  qualified.isFinite,
                  accepted >= 0,
                  qualified >= 0,
                  accepted == qualified,
                  validAccuracy(presentation.acceptedObservedSpeedAccuracyMetersPerSecond),
                  presentation.observationContinuity == .noRecordedSelectedSourceEvidenceLoss,
                  presentation.permitsObservedMaximumWording,
                  !presentation.requiresQualityDisclosure else {
                return nil
            }

            return RideHistoryObservedPeakConsumerProjection(
                sessionID: presentation.sessionID,
                selectedSource: presentation.selectedSource,
                state: .qualifiedObservedMaximum(metersPerSecond: qualified)
            )
        }
    }

    private static func validAccuracy(_ metersPerSecond: Double?) -> Bool {
        metersPerSecond.map { $0.isFinite && $0 >= 0 } ?? true
    }
}
