import Foundation

/// Fail-closed consumer shape for Ride Details, history summaries, and accessibility.
///
/// Construction is sealed inside this file. External app/UI code can inspect a projection
/// minted by NembraCore but cannot create one from a number or presentation-state enum case.
/// The numeric value, disclosure requirement, and maximum-wording authority are all derived
/// from one private storage state so contradictory combinations cannot be created through the
/// public API.
///
/// This is derived presentation state only. It is intentionally not Codable, must not be
/// persisted as evidence, and never upgrades retained history into fresh telemetry.
public struct RideHistoryObservedPeakConsumerProjection: Equatable, Sendable {
    fileprivate enum Storage: Equatable, Sendable {
        case unavailable
        case acceptedObservation(metersPerSecond: Double)
        case qualifiedObservedMaximum(metersPerSecond: Double)
    }

    public let sessionID: UUID
    public let selectedSource: SpeedTelemetrySource
    private let storage: Storage

    /// Reuses NembraCore's existing product-state vocabulary. The enum value is descriptive;
    /// observed-maximum wording authority remains this sealed projection's
    /// `permitsObservedMaximumWording` property.
    public var state: RideHistoryObservedPeakPresentationState {
        switch storage {
        case .unavailable:
            return .observedPeakUnavailable
        case .acceptedObservation:
            return .unqualifiedAcceptedObservation
        case .qualifiedObservedMaximum:
            return .qualifiedObservedMaximum
        }
    }

    /// Numeric value legitimate for this exact sealed presentation. Nil means no accepted
    /// selected-source peak evidence exists; legitimate observed zero remains `0`.
    public var speedMetersPerSecond: Double? {
        switch storage {
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
        if case .acceptedObservation = storage {
            return true
        }
        return false
    }

    /// The sole public consumer-level observed-maximum wording authority. This can be true
    /// only on a sealed projection minted from quality-qualified durable evidence.
    public var permitsObservedMaximumWording: Bool {
        if case .qualifiedObservedMaximum = storage {
            return true
        }
        return false
    }

    fileprivate init(
        sessionID: UUID,
        selectedSource: SpeedTelemetrySource,
        storage: Storage
    ) {
        self.sessionID = sessionID
        self.selectedSource = selectedSource
        self.storage = storage
    }
}

/// Converts the module-owned durable-history presentation into a sealed consumer projection.
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
                storage: .unavailable
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
                storage: .acceptedObservation(metersPerSecond: accepted)
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
                storage: .qualifiedObservedMaximum(metersPerSecond: qualified)
            )
        }
    }

    private static func validAccuracy(_ metersPerSecond: Double?) -> Bool {
        metersPerSecond.map { $0.isFinite && $0 >= 0 } ?? true
    }
}
