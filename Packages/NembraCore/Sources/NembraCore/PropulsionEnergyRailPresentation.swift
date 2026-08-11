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
/// physical claims. The accepted target is deliberately separate from the interpolated rail position so
/// accessibility presentation can avoid spatial display-clock motion without reverse-engineering watts.
///
/// The type deliberately carries no regen/direction/rated-maximum semantics. Those meanings require
/// separate accepted physical authority and must not be inferred from a moving rail or a signed value.
public struct PropulsionEnergyRailPresentation: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?

    /// Display-clock normalized propulsion geometry in `0...1`.
    public let railFraction: Double?
    /// Exact accepted measurement normalized against the same admitted presentation scale.
    /// This is a non-interpolated presentation target, never telemetry evidence.
    public let acceptedTargetFraction: Double?
    /// Display-only marker derived from an accepted peak inside the canonical hold window.
    public let acceptedPeakMarkerFraction: Double?
    /// Provenance of the compatible presentation scale used to normalize the rail.
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    /// True only when the source is a fresh accepted measurement and complete normalized rail geometry exists.
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
    /// live rail motion and remove normalized geometry. Live geometry is admitted only when both the
    /// interpolated display position and the non-interpolated accepted target are valid under one scale.
    var energyRailPresentation: PropulsionEnergyRailPresentation {
        switch measurement {
        case let .live(accepted):
            guard accepted.identity == identity else {
                return unavailableEnergyRailPresentation()
            }

            let renderFraction = validEnergyRailFraction(visualPropulsionFraction)
            let targetFraction = validEnergyRailFraction(acceptedPropulsionFraction)
            let hasCompleteGeometry = renderFraction != nil
                && targetFraction != nil
                && scaleOrigin != nil
            let admittedRailFraction = hasCompleteGeometry ? renderFraction : nil
            let admittedTargetFraction = hasCompleteGeometry ? targetFraction : nil
            let peakMarker = hasCompleteGeometry
                ? validEnergyRailFraction(recentAcceptedPeakMarkerFraction)
                : nil
            let admittedScaleOrigin = hasCompleteGeometry ? scaleOrigin : nil

            return PropulsionEnergyRailPresentation(
                identity: identity,
                currentness: .live,
                acceptedWatts: accepted.watts,
                railFraction: admittedRailFraction,
                acceptedTargetFraction: admittedTargetFraction,
                acceptedPeakMarkerFraction: peakMarker,
                scaleOrigin: admittedScaleOrigin,
                allowsLiveMotion: hasCompleteGeometry
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
