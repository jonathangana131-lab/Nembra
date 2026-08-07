/// One cockpit-facing propulsion presentation cut derived from a single canonical
/// gauge frame.
///
/// The nested snapshots intentionally remain separate instead of flattening their
/// fields:
/// - `cockpit` owns accepted numeric power plus render-only band/peak positions;
/// - `accessibility` owns accepted-only assistive-technology semantics;
/// - `observedScaleRegion` owns render-independent near-observed-scale semantics.
///
/// Keeping those concerns typed prevents a future SwiftUI cockpit from treating a
/// 60 Hz interpolated render value as telemetry, VoiceOver truth, or evidence for
/// "Near observed max" wording.
public struct PropulsionGaugeCockpitPresentationSnapshot: Equatable, Sendable {
    public let cockpit: PropulsionGaugeCockpitSnapshot
    public let accessibility: PropulsionGaugeAccessibilitySnapshot
    public let observedScaleRegion: PropulsionObservedScaleRegionSnapshot

    fileprivate init(
        cockpit: PropulsionGaugeCockpitSnapshot,
        accessibility: PropulsionGaugeAccessibilitySnapshot,
        observedScaleRegion: PropulsionObservedScaleRegionSnapshot
    ) {
        self.cockpit = cockpit
        self.accessibility = accessibility
        self.observedScaleRegion = observedScaleRegion
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Produces the complete propulsion handoff for one cockpit render tick.
    ///
    /// The canonical frame is evaluated exactly once. Every nested projection is
    /// then derived from that same immutable presentation cut, so high-frequency
    /// render motion cannot race a separately evaluated accepted-power/semantic
    /// snapshot during the same UI update.
    ///
    /// This remains presentation-only composition. It does not create a telemetry
    /// sample, persist evidence, infer throttle position, prove regen, or assign a
    /// physical maximum to the compatible observed presentation scale.
    func cockpitPresentationSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        observedScalePolicy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionGaugeCockpitPresentationSnapshot {
        let frame = frame(
            atUptimeNanoseconds: now,
            scale: scale
        )
        let accessibility = accessibilitySnapshot(
            from: frame,
            scale: scale
        )

        return PropulsionGaugeCockpitPresentationSnapshot(
            cockpit: cockpitSnapshot(from: frame),
            accessibility: accessibility,
            observedScaleRegion: observedScaleRegionSnapshot(
                from: accessibility,
                policy: observedScalePolicy
            )
        )
    }
}