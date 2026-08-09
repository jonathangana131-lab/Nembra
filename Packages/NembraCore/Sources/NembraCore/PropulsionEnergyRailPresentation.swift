/// Product-facing currentness for the Nembra Energy Rail.
///
/// This is intentionally smaller than propulsion evidence provenance. The Energy Rail only needs to
/// distinguish a fresh accepted measurement, retained accepted evidence, and no usable measurement.
/// It must never infer freshness from render motion.
public enum PropulsionEnergyRailCurrentness: Equatable, Sendable {
    case live
    case retained
    case unavailable
}

/// Truth-preserving presentation contract for the Nembra Energy Rail.
///
/// `acceptedWatts` comes only from the canonical accepted cockpit measurement. `railFraction`,
/// `acceptedTargetFraction`, and `acceptedPeakMarkerFraction` are display-only geometry and must never
/// be persisted or promoted to telemetry, protocol evidence, historical peaks, range learning, or
/// physical claims. `acceptedTargetFraction` differs from `railFraction` by staying fixed at the
/// normalized accepted target while the latter may move on the display clock.
///
/// The type deliberately carries no regen/direction/rated-maximum semantics. Those meanings require
/// separate accepted physical authority and must not be inferred from a moving rail or a signed value.
public struct PropulsionEnergyRailPresentation: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?

    /// Display-only normalized propulsion geometry in `0...1` at the current render clock.
    public let railFraction: Double?
    /// Display-only normalized geometry for the exact accepted target in `0...1`.
    /// This is stable between render frames for one accepted measurement and is the appropriate
    /// rail position for Reduce Motion snapping. It is not a second measurement.
    public let acceptedTargetFraction: Double?
    /// Display-only marker derived from an accepted peak inside the canonical hold window.
    public let acceptedPeakMarkerFraction: Double?
    /// Provenance of the compatible presentation scale used to normalize the rail.
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    /// True only when the source is a fresh accepted measurement and normalized render geometry exists.
    /// A SwiftUI consumer may use this to drive localized display-clock motion; it is never evidence.
    public let allowsLiveMotion: Bool

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedWatts: Double?,
        railFraction: Double?,
        acceptedTargetFraction: Double?,
        acceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?,
        allowsLiveMotion: Bool
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedWatts = acceptedWatts
        self.railFraction = railFraction
        self.acceptedTargetFraction = acceptedTargetFraction
        self.acceptedPeakMarkerFraction = acceptedPeakMarkerFraction
        self.scaleOrigin = scaleOrigin
        self.allowsLiveMotion = allowsLiveMotion
    }
}

public extension PropulsionGaugeCockpitSnapshot {
    /// Projects the canonical cockpit snapshot into the narrower visual contract consumed by an Energy Rail.
    ///
    /// Numeric truth and render geometry remain deliberately independent: a live accepted watt value may
    /// remain present even when no compatible scale exists, while retained/unavailable states always stop
    /// live rail motion and remove normalized geometry.
    var energyRailPresentation: PropulsionEnergyRailPresentation {
        switch measurement {
        case let .live(accepted):
            guard accepted.identity == identity else {
                return unavailableEnergyRailPresentation()
            }

            let railFraction = validEnergyRailFraction(visualPropulsionFraction)
            let acceptedTargetFraction = validEnergyRailFraction(acceptedPropulsionFraction)
            let peakMarker = railFraction == nil
                ? nil
                : validEnergyRailFraction(recentAcceptedPeakMarkerFraction)
            let hasAdmittedGeometry = railFraction != nil || acceptedTargetFraction != nil
            let admittedScaleOrigin = hasAdmittedGeometry ? scaleOrigin : nil

            return PropulsionEnergyRailPresentation(
                identity: identity,
                currentness: .live,
                acceptedWatts: accepted.watts,
                railFraction: railFraction,
                acceptedTargetFraction: acceptedTargetFraction,
                acceptedPeakMarkerFraction: peakMarker,
                scaleOrigin: admittedScaleOrigin,
                allowsLiveMotion: railFraction != nil
            )

        case let .retained(accepted):
            guard accepted.identity == identity else {
                return unavailableEnergyRailPresentation()
            }

            return PropulsionEnergyRailPresentation(
                identity: identity,
                currentness: .retained,
                acceptedWatts: accepted.watts,
                railFraction: nil,
                acceptedTargetFraction: nil,
                acceptedPeakMarkerFraction: nil,
                scaleOrigin: nil,
                allowsLiveMotion: false
            )

        case .unavailable:
            return unavailableEnergyRailPresentation()
        }
    }

    private func unavailableEnergyRailPresentation() -> PropulsionEnergyRailPresentation {
        PropulsionEnergyRailPresentation(
            identity: identity,
            currentness: .unavailable,
            acceptedWatts: nil,
            railFraction: nil,
            acceptedTargetFraction: nil,
            acceptedPeakMarkerFraction: nil,
            scaleOrigin: nil,
            allowsLiveMotion: false
        )
    }

    private func validEnergyRailFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else {
            return nil
        }
        return value
    }
}
