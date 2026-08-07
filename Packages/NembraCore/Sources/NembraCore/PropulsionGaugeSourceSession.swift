/// Source-lifecycle owner for propulsion-gauge presentation.
///
/// `PropulsionGaugeDisplayModel` deliberately owns accepted-measurement chronology and render-only
/// interpolation. Real asynchronous transports also need to fence lifecycle callbacks: a delayed
/// disconnect/interruption from an older source generation must not hide a newer accepted measurement,
/// while an interruption observed before the first sample must still prevent that retired generation
/// from being accepted later.
///
/// This wrapper does not mint measurement authority, derive watts, choose a physical ES80 source, or
/// turn lifecycle events into zero-power samples. It only binds source-owned authority/generation
/// lifecycle evidence to the accepted presentation model.
public struct PropulsionGaugeSourceSession: Sendable {
    public enum InterruptionDisposition: String, Equatable, Sendable {
        /// The source generation was fenced before this session had accepted any measurement.
        case fencedBeforeFirstMeasurement
        /// The interruption applies to the authority currently presented and is at least as new as
        /// that authority's accepted generation, so live presentation became unavailable.
        case appliedToActiveAuthority
        /// A different authority was interrupted. Its generation was fenced without disturbing the
        /// currently presented authority.
        case fencedInactiveAuthority
        /// The interruption belongs to an older generation than the currently accepted generation
        /// for the same authority. It was recorded but cannot hide newer accepted evidence.
        case ignoredOlderGeneration
    }

    private struct AcceptedSourceEpoch: Equatable, Sendable {
        let authority: PropulsionPowerSampleAuthority
        let continuityGeneration: UInt64
    }

    private var displayModel: PropulsionGaugeDisplayModel
    private var activeAcceptedEpoch: AcceptedSourceEpoch?
    private var retiredGenerationByAuthority: [PropulsionPowerSampleAuthority: UInt64] = [:]

    public var identity: PropulsionGaugeIdentity { displayModel.identity }
    public var policy: PropulsionGaugeMotionPolicy { displayModel.policy }

    public init(identity: PropulsionGaugeIdentity, policy: PropulsionGaugeMotionPolicy) {
        self.displayModel = PropulsionGaugeDisplayModel(identity: identity, policy: policy)
    }

    /// Accepts one already-authoritative observation after applying lifecycle retirement fences.
    ///
    /// Retirement is checked before the display model sees the sample so an interruption that arrived
    /// before any measurement, or while another authority was active, cannot later be bypassed by a
    /// delayed callback from that retired generation.
    public mutating func accept(_ sample: PropulsionPowerSample) throws {
        if let retiredGeneration = retiredGenerationByAuthority[sample.authority],
           sample.continuityGeneration <= retiredGeneration {
            throw PropulsionGaugeDisplayError.retiredContinuityGeneration
        }

        try displayModel.accept(sample)
        activeAcceptedEpoch = AcceptedSourceEpoch(
            authority: sample.authority,
            continuityGeneration: sample.continuityGeneration
        )
    }

    /// Records source-owned unavailability without allowing stale lifecycle callbacks to invalidate
    /// newer accepted presentation.
    ///
    /// - Important: `continuityGeneration` belongs to the same source/authority namespace that mints
    ///   `PropulsionPowerSample.continuityGeneration`. Callers must not synthesize a new generation in
    ///   presentation code merely to force a state transition.
    @discardableResult
    public mutating func markUnavailable(
        authority: PropulsionPowerSampleAuthority,
        continuityGeneration: UInt64
    ) -> InterruptionDisposition {
        let existingRetiredGeneration = retiredGenerationByAuthority[authority]
        retiredGenerationByAuthority[authority] = max(
            existingRetiredGeneration ?? continuityGeneration,
            continuityGeneration
        )

        guard let activeAcceptedEpoch else {
            return .fencedBeforeFirstMeasurement
        }

        guard activeAcceptedEpoch.authority == authority else {
            return .fencedInactiveAuthority
        }

        guard continuityGeneration >= activeAcceptedEpoch.continuityGeneration else {
            return .ignoredOlderGeneration
        }

        // The display model retires its currently active accepted generation and preserves the last
        // accepted numeric measurement as unavailable metadata rather than manufacturing zero watts.
        // This wrapper's stronger retirement floor additionally covers a source generation newer than
        // the last accepted sample (for example, a reconnect attempt that failed before yielding data).
        displayModel.markUnavailable()
        return .appliedToActiveAuthority
    }

    public func frame(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeFrame {
        displayModel.frame(atUptimeNanoseconds: now, scale: scale)
    }

    public func accessibilitySnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeAccessibilitySnapshot {
        displayModel.accessibilitySnapshot(atUptimeNanoseconds: now, scale: scale)
    }
}
