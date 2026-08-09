/// Canonical app-facing Energy Rail projection.
///
/// This is the only package projection intended to cross into the SwiftUI adapter. It deliberately
/// fuses the semantic/accepted-target presentation with the dual-clock render presentation while
/// preserving their different authority classes. App code must not reconstruct one from the other.
public struct PropulsionEnergyRailAppProjection: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?
    public let displayWatts: Double?
    public let railFraction: Double?
    public let acceptedTargetFraction: Double?
    public let acceptedPeakMarkerFraction: Double?
    public let allowsLiveMotion: Bool

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedWatts: Double?,
        displayWatts: Double?,
        railFraction: Double?,
        acceptedTargetFraction: Double?,
        acceptedPeakMarkerFraction: Double?,
        allowsLiveMotion: Bool
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedWatts = acceptedWatts
        self.displayWatts = displayWatts
        self.railFraction = railFraction
        self.acceptedTargetFraction = acceptedTargetFraction
        self.acceptedPeakMarkerFraction = acceptedPeakMarkerFraction
        self.allowsLiveMotion = allowsLiveMotion
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Produces the one app-facing Energy Rail subject at a single render uptime.
    ///
    /// The semantic projection owns accepted watts/currentness/accepted target. The render projection
    /// owns display-only watts and interpolated rail/peak geometry. The two projections must agree on
    /// identity, currentness, and accepted numeric truth before live geometry is admitted. Any
    /// disagreement fails closed to unavailable rather than allowing SwiftUI to splice mismatched
    /// generations.
    func energyRailAppProjection(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionEnergyRailAppProjection {
        let semantic = cockpitSnapshot(
            atUptimeNanoseconds: now,
            scale: scale
        ).energyRailPresentation
        let render = energyRailRenderPresentation(
            atUptimeNanoseconds: now,
            scale: scale
        )

        guard semantic.identity == render.identity,
              semantic.currentness == render.currentness,
              equalOptionalFiniteNonnegative(semantic.acceptedWatts, render.acceptedWatts) else {
            return unavailableEnergyRailAppProjection(identity: semantic.identity)
        }

        switch semantic.currentness {
        case .live:
            guard let acceptedWatts = semantic.acceptedWatts,
                  acceptedWatts.isFinite,
                  acceptedWatts >= 0 else {
                return unavailableEnergyRailAppProjection(identity: semantic.identity)
            }

            // The rail remains a valid live presentation after interpolation settles. Do not couple
            // rail visibility to `allowsDisplayWattsMotion`: that flag only says whether the watt
            // numeral is currently between accepted measurements. The sealed SwiftUI state has one
            // live-motion admission bit, so bind it to complete live rail geometry; a settled
            // `displayWatts == acceptedWatts` value is static naturally because its value no longer
            // changes.
            let motionAllowed = semantic.allowsLiveMotion && render.allowsRailMotion

            return PropulsionEnergyRailAppProjection(
                identity: semantic.identity,
                currentness: .live,
                acceptedWatts: acceptedWatts,
                displayWatts: validWatts(render.displayWatts) ?? acceptedWatts,
                railFraction: validFraction(render.railFraction),
                acceptedTargetFraction: validFraction(semantic.acceptedTargetFraction),
                acceptedPeakMarkerFraction: validFraction(render.acceptedPeakMarkerFraction),
                allowsLiveMotion: motionAllowed
            )

        case .retained:
            guard let acceptedWatts = semantic.acceptedWatts,
                  acceptedWatts.isFinite,
                  acceptedWatts >= 0 else {
                return unavailableEnergyRailAppProjection(identity: semantic.identity)
            }

            return PropulsionEnergyRailAppProjection(
                identity: semantic.identity,
                currentness: .retained,
                acceptedWatts: acceptedWatts,
                displayWatts: acceptedWatts,
                railFraction: nil,
                acceptedTargetFraction: nil,
                acceptedPeakMarkerFraction: nil,
                allowsLiveMotion: false
            )

        case .unavailable:
            return unavailableEnergyRailAppProjection(identity: semantic.identity)
        }
    }

    private func unavailableEnergyRailAppProjection(
        identity: PropulsionGaugeIdentity
    ) -> PropulsionEnergyRailAppProjection {
        PropulsionEnergyRailAppProjection(
            identity: identity,
            currentness: .unavailable,
            acceptedWatts: nil,
            displayWatts: nil,
            railFraction: nil,
            acceptedTargetFraction: nil,
            acceptedPeakMarkerFraction: nil,
            allowsLiveMotion: false
        )
    }

    private func validWatts(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func validFraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0, value <= 1 else { return nil }
        return value
    }

    private func equalOptionalFiniteNonnegative(_ lhs: Double?, _ rhs: Double?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.isFinite && lhs >= 0 && rhs.isFinite && rhs >= 0 && lhs == rhs
        default:
            return false
        }
    }
}
