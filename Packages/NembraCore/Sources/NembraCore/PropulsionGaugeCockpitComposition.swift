/// One product-facing propulsion snapshot built from a single canonical gauge frame.
///
/// The two projections remain deliberately typed by their existing truth contracts:
/// - `cockpit` owns accepted numeric watts plus render-only band/peak presentation;
/// - `observedScaleRegion` owns accepted-measurement near-edge semantics and verified wording eligibility.
///
/// Construction is file-private so callers cannot pair projections from different display ticks.
public struct PropulsionGaugeCockpitCompositionSnapshot: Equatable, Sendable {
    public let cockpit: PropulsionGaugeCockpitSnapshot
    public let observedScaleRegion: PropulsionObservedScaleRegionSnapshot

    fileprivate init(
        cockpit: PropulsionGaugeCockpitSnapshot,
        observedScaleRegion: PropulsionObservedScaleRegionSnapshot
    ) {
        self.cockpit = cockpit
        self.observedScaleRegion = observedScaleRegion
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Builds the complete propulsion-cockpit handoff from exactly one canonical
    /// `PropulsionGaugeFrame` evaluation for this display tick.
    ///
    /// This is the preferred future 60 Hz product integration seam. It prevents a
    /// SwiftUI caller from independently asking the display model for render motion
    /// and accepted observed-scale semantics at slightly different clocks, while
    /// preserving the existing separation between measurement truth and display
    /// interpolation.
    ///
    /// Render fractions remain presentation only. Neither this snapshot nor its
    /// interpolated values may be persisted or reused as telemetry, ride, peak,
    /// battery/range, acceleration, calibration, or protocol evidence.
    func cockpitCompositionSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        observedScaleRegionPolicy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionGaugeCockpitCompositionSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let cockpit = cockpitSnapshot(from: frame)
        let accepted = accessibilitySnapshot(from: frame, scale: scale)
        let observedScaleRegion = observedScaleRegionSnapshot(
            from: accepted,
            policy: observedScaleRegionPolicy
        )

        return PropulsionGaugeCockpitCompositionSnapshot(
            cockpit: cockpit,
            observedScaleRegion: observedScaleRegion
        )
    }
}