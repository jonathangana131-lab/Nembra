/// Source-lifecycle owner for propulsion-gauge presentation.
///
/// `PropulsionGaugeDisplayModel` deliberately owns accepted-measurement chronology and render-only
/// interpolation. Real asynchronous transports also need to fence lifecycle callbacks: a delayed
/// disconnect/interruption from an older source generation must not hide a newer accepted measurement,
/// while an interruption observed before the first sample must still prevent that retired generation
/// from being accepted later.
///
/// This wrapper does not mint measurement authority, derive watts, choose a physical ES80 source, or
/// turn lifecycle events into zero-power samples. It binds source-owned authority/generation lifecycle
/// evidence to the canonical accepted/display model, then forwards the already-accepted product
/// projections so integration code does not recreate truth policy in SwiftUI.
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

    /// Render-clock policy only. Callers may tune this independently (for example for Reduce Motion)
    /// without changing accepted-measurement currentness.
    public var animationPolicy: PropulsionGaugeAnimationPolicy { displayModel.animationPolicy }

    /// Accepted-measurement currentness only. This must not be implicitly rewritten when visual
    /// response is tuned.
    public var freshnessPolicy: PropulsionGaugeFreshnessPolicy { displayModel.freshnessPolicy }

    /// Source-compatible adapter for callers that still consume the pre-split policy shape.
    /// New integration code should use `animationPolicy` and `freshnessPolicy` independently.
    public var policy: PropulsionGaugeMotionPolicy { displayModel.policy }

    /// Preferred initializer. Source integration must keep render tuning and measurement freshness
    /// structurally separate so accessibility or visual changes cannot alter evidence currentness.
    public init(
        identity: PropulsionGaugeIdentity,
        animationPolicy: PropulsionGaugeAnimationPolicy,
        freshnessPolicy: PropulsionGaugeFreshnessPolicy
    ) {
        self.displayModel = PropulsionGaugeDisplayModel(
            identity: identity,
            animationPolicy: animationPolicy,
            freshnessPolicy: freshnessPolicy
        )
    }

    /// Compatibility adapter for the original combined policy shape.
    public init(identity: PropulsionGaugeIdentity, policy: PropulsionGaugeMotionPolicy) {
        self.displayModel = PropulsionGaugeDisplayModel(identity: identity, policy: policy)
    }

    /// Accepts one already-authoritative observation after applying lifecycle retirement fences.
    ///
    /// Identity is rejected before lifecycle state is consulted so a cross-identity sample cannot be
    /// classified using this session's retirement history. After that boundary, retirement is checked
    /// before the display model sees the sample so an interruption that arrived before any measurement,
    /// or while another authority was active, cannot later be bypassed by a delayed callback from that
    /// retired generation.
    public mutating func accept(_ sample: PropulsionPowerSample) throws {
        guard sample.identity == identity else {
            throw PropulsionGaugeDisplayError.identityMismatch
        }

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

    /// Lowest-level canonical frame. `displayWatts` remains render-only and must not be persisted or
    /// treated as an accepted measurement by callers.
    public func frame(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeFrame {
        displayModel.frame(atUptimeNanoseconds: now, scale: scale)
    }

    /// Accepted-only accessibility projection. VoiceOver/currentness semantics remain owned by the
    /// canonical display model rather than source-integration call sites.
    public func accessibilitySnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeAccessibilitySnapshot {
        displayModel.accessibilitySnapshot(atUptimeNanoseconds: now, scale: scale)
    }

    /// Cockpit projection from merged propulsion-cockpit semantics. Accepted numeric power remains
    /// separate from render-only band/peak motion; this wrapper does not reconstruct that policy.
    public func cockpitSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeCockpitSnapshot {
        displayModel.cockpitSnapshot(atUptimeNanoseconds: now, scale: scale)
    }

    /// Canonical app-facing Energy Rail subject from this exact lifecycle owner.
    ///
    /// Integration code must use this forwarding seam rather than reconstructing a
    /// projection from `frame`/`cockpitSnapshot`: the display model owns the required
    /// semantic/render cross-binding and the source session owns interruption fences.
    public func energyRailAppProjection(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionEnergyRailAppProjection {
        displayModel.energyRailAppProjection(
            atUptimeNanoseconds: now,
            scale: scale
        )
    }

    /// Accepted observed-scale semantic projection from the canonical model. In particular, the
    /// returned verified-wording gate remains authority-sealed and is not inferred from render motion.
    public func observedScaleRegionSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        policy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionObservedScaleRegionSnapshot {
        displayModel.observedScaleRegionSnapshot(
            atUptimeNanoseconds: now,
            scale: scale,
            policy: policy
        )
    }
}
