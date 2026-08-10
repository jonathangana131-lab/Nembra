/// Dual-clock render contract for the Nembra Energy Rail.
///
/// `acceptedWatts` is the latest accepted measurement and is the only numeric
/// value in this projection that may drive user-facing semantic/accessibility
/// truth. `displayWatts` is render-only interpolation from the canonical gauge
/// frame. It must never become telemetry, persistence, peak evidence, range
/// learning, protocol evidence, or a physical claim.
public struct PropulsionEnergyRailRenderPresentation: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?

    /// Render-only watt value for localized rolling-number presentation.
    /// In retained state this settles exactly to `acceptedWatts`; unavailable
    /// state carries no numeric value.
    public let displayWatts: Double?
    /// Canonical gauge-frame origin for the render-only watt channel.
    public let displayOrigin: PropulsionGaugeFrameOrigin

    /// Render-only normalized propulsion geometry in `0...1`.
    public let railFraction: Double?
    /// Render-only marker derived from accepted peak evidence inside the
    /// canonical display hold window.
    public let acceptedPeakMarkerFraction: Double?
    /// Presentation-scale provenance only.
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    /// True only while the canonical display model is actively interpolating
    /// watts between accepted measurements. This is presentation permission,
    /// never evidence freshness.
    public let allowsDisplayWattsMotion: Bool
    /// True only for live evidence with usable normalized rail geometry.
    public let allowsRailMotion: Bool

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedWatts: Double?,
        displayWatts: Double?,
        displayOrigin: PropulsionGaugeFrameOrigin,
        railFraction: Double?,
        acceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?,
        allowsDisplayWattsMotion: Bool,
        allowsRailMotion: Bool
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedWatts = acceptedWatts
        self.displayWatts = displayWatts
        self.displayOrigin = displayOrigin
        self.railFraction = railFraction
        self.acceptedPeakMarkerFraction = acceptedPeakMarkerFraction
        self.scaleOrigin = scaleOrigin
        self.allowsDisplayWattsMotion = allowsDisplayWattsMotion
        self.allowsRailMotion = allowsRailMotion
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Evaluates the canonical gauge frame exactly once and exposes separate
    /// measurement-clock and display-clock watt channels for Energy Rail UI.
    ///
    /// This intentionally does not reuse `cockpitSnapshot`, because that
    /// projection strips interpolated watts by design. Reconstructing display
    /// watts from rail geometry would lose truth and scale semantics.
    func energyRailRenderPresentation(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionEnergyRailRenderPresentation {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        return energyRailRenderPresentation(from: frame)
    }

    private func energyRailRenderPresentation(
        from frame: PropulsionGaugeFrame
    ) -> PropulsionEnergyRailRenderPresentation {
        switch frame.availability {
        case .live:
            guard let acceptedWatts = validEnergyRailWatts(frame.latestAcceptedWatts),
                  let displayWatts = validEnergyRailWatts(frame.displayWatts),
                  hasCompleteAcceptedEnergyRailProvenance(frame) else {
                return unavailableEnergyRailRenderPresentation(frame)
            }

            let railFraction = validEnergyRailRenderFraction(frame.normalizedPropulsion)
            let peakMarker = railFraction == nil
                ? nil
                : validEnergyRailRenderFraction(frame.acceptedPeakNormalized)
            let admittedScaleOrigin = railFraction == nil ? nil : frame.scaleOrigin
            let isInterpolating = frame.origin == .visuallyInterpolated
                && displayWatts != acceptedWatts

            return PropulsionEnergyRailRenderPresentation(
                identity: frame.identity,
                currentness: .live,
                acceptedWatts: acceptedWatts,
                displayWatts: displayWatts,
                displayOrigin: frame.origin,
                railFraction: railFraction,
                acceptedPeakMarkerFraction: peakMarker,
                scaleOrigin: admittedScaleOrigin,
                allowsDisplayWattsMotion: isInterpolating,
                allowsRailMotion: railFraction != nil
            )

        case .retained:
            guard let acceptedWatts = validEnergyRailWatts(frame.latestAcceptedWatts),
                  hasCompleteAcceptedEnergyRailProvenance(frame) else {
                return unavailableEnergyRailRenderPresentation(frame)
            }

            // Retained evidence is intentionally static. Never carry a stale
            // interpolated midpoint forward after evidence stops being live.
            return PropulsionEnergyRailRenderPresentation(
                identity: frame.identity,
                currentness: .retained,
                acceptedWatts: acceptedWatts,
                displayWatts: acceptedWatts,
                displayOrigin: .retainedAcceptedMeasurement,
                railFraction: nil,
                acceptedPeakMarkerFraction: nil,
                scaleOrigin: nil,
                allowsDisplayWattsMotion: false,
                allowsRailMotion: false
            )

        case .unavailable:
            return unavailableEnergyRailRenderPresentation(frame)
        }
    }

    private func hasCompleteAcceptedEnergyRailProvenance(
        _ frame: PropulsionGaugeFrame
    ) -> Bool {
        frame.latestAcceptedReceiptSequenceNumber != nil
            && frame.latestAcceptedUptimeNanoseconds != nil
            && frame.latestAcceptedContinuityGeneration != nil
            && frame.latestAuthority != nil
    }

    private func validEnergyRailWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func validEnergyRailRenderFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else {
            return nil
        }
        return value
    }

    private func unavailableEnergyRailRenderPresentation(
        _ frame: PropulsionGaugeFrame
    ) -> PropulsionEnergyRailRenderPresentation {
        PropulsionEnergyRailRenderPresentation(
            identity: frame.identity,
            currentness: .unavailable,
            acceptedWatts: nil,
            displayWatts: nil,
            displayOrigin: frame.origin,
            railFraction: nil,
            acceptedPeakMarkerFraction: nil,
            scaleOrigin: nil,
            allowsDisplayWattsMotion: false,
            allowsRailMotion: false
        )
    }
}