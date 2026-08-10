/// Canonical app-facing Energy Rail projection.
///
/// This is the only package projection intended to cross into the SwiftUI adapter. It deliberately
/// fuses accepted/semantic truth, accessibility cadence, and dual-clock render presentation while
/// preserving their different authority classes. App code must not reconstruct one from the other.
///
/// The sealed accepted measurement is carried across this boundary intact so downstream UI cannot
/// erase whether the numeric truth is Simulator-only or package-sealed verified vehicle evidence.
/// Receipt/generation/uptime provenance remains attached for stale-generation rejection; it is not
/// display telemetry and must never be synthesized by SwiftUI.
public struct PropulsionEnergyRailAppProjection: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedMeasurement: PropulsionGaugeCockpitAcceptedMeasurement?

    /// Stable semantic/accessibility state. SwiftUI should key VoiceOver-facing updates on
    /// `accessibilityPresentation.semanticRevision`, never on this projection's render-changing
    /// display watts or rail geometry.
    public let accessibilityPresentation: PropulsionEnergyRailAccessibilityPresentation

    public let displayWatts: Double?
    public let railFraction: Double?
    public let acceptedTargetFraction: Double?
    public let acceptedPeakMarkerFraction: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?
    public let allowsLiveMotion: Bool

    /// Accepted numeric truth is always read from the sealed measurement subject so watts cannot
    /// drift from its authority/chronology tuple while crossing the app boundary.
    public var acceptedWatts: Double? { acceptedMeasurement?.watts }

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedMeasurement: PropulsionGaugeCockpitAcceptedMeasurement?,
        accessibilityPresentation: PropulsionEnergyRailAccessibilityPresentation,
        displayWatts: Double?,
        railFraction: Double?,
        acceptedTargetFraction: Double?,
        acceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?,
        allowsLiveMotion: Bool
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedMeasurement = acceptedMeasurement
        self.accessibilityPresentation = accessibilityPresentation
        self.displayWatts = displayWatts
        self.railFraction = railFraction
        self.acceptedTargetFraction = acceptedTargetFraction
        self.acceptedPeakMarkerFraction = acceptedPeakMarkerFraction
        self.scaleOrigin = scaleOrigin
        self.allowsLiveMotion = allowsLiveMotion
    }
}

public extension PropulsionEnergyRailAppProjection {
    /// Applies source-owned lifecycle currentness without allowing presentation code
    /// to upgrade package truth. This is intentionally one-way:
    /// - `.live` preserves only an already-live sealed package projection;
    /// - `.retained` may demote an accepted live/retained measurement to static
    ///   last-known semantics while preserving its exact receipt identity;
    /// - `.unavailable` strips all numeric/geometry presentation.
    ///
    /// The method never creates an accepted measurement, receipt, generation, watt
    /// value, scale, peak, or render position. It only constrains an existing sealed
    /// projection using currentness owned by the accepted source boundary.
    func constrained(
        toSourceCurrentness sourceCurrentness: PropulsionEnergyRailCurrentness
    ) -> PropulsionEnergyRailAppProjection {
        switch sourceCurrentness {
        case .live:
            guard currentness == .live else {
                return sourceUnavailableProjection()
            }
            return self

        case .retained:
            guard currentness != .unavailable,
                  let acceptedMeasurement,
                  acceptedMeasurement.identity == identity,
                  acceptedMeasurement.watts.isFinite,
                  acceptedMeasurement.watts >= 0,
                  let acceptedRevision = accessibilityPresentation.acceptedRevision,
                  acceptedRevision.authority == acceptedMeasurement.authority,
                  acceptedRevision.continuityGeneration == acceptedMeasurement.continuityGeneration,
                  acceptedRevision.receiptSequenceNumber == acceptedMeasurement.receiptSequenceNumber,
                  acceptedRevision.receivedAtUptimeNanoseconds == acceptedMeasurement.receivedAtUptimeNanoseconds else {
                return sourceUnavailableProjection()
            }

            return PropulsionEnergyRailAppProjection(
                identity: identity,
                currentness: .retained,
                acceptedMeasurement: acceptedMeasurement,
                accessibilityPresentation: PropulsionEnergyRailAccessibilityPresentation(
                    identity: identity,
                    currentness: .retained,
                    acceptedWatts: acceptedMeasurement.watts,
                    acceptedRevision: acceptedRevision
                ),
                displayWatts: acceptedMeasurement.watts,
                railFraction: nil,
                acceptedTargetFraction: nil,
                acceptedPeakMarkerFraction: nil,
                scaleOrigin: nil,
                allowsLiveMotion: false
            )

        case .unavailable:
            return sourceUnavailableProjection()
        }
    }

    private func sourceUnavailableProjection() -> PropulsionEnergyRailAppProjection {
        PropulsionEnergyRailAppProjection(
            identity: identity,
            currentness: .unavailable,
            acceptedMeasurement: nil,
            accessibilityPresentation: .unavailable(identity: identity),
            displayWatts: nil,
            railFraction: nil,
            acceptedTargetFraction: nil,
            acceptedPeakMarkerFraction: nil,
            scaleOrigin: nil,
            allowsLiveMotion: false
        )
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Produces the one app-facing Energy Rail subject at a single render uptime.
    ///
    /// The cockpit projection owns the sealed accepted measurement and semantic target. The render
    /// projection owns display-only watts and interpolated rail/peak geometry. The accessibility
    /// projection owns accepted semantic cadence. All three must agree on identity, currentness, and
    /// accepted numeric truth before the package admits them across one app boundary. Any disagreement
    /// fails closed to unavailable rather than allowing SwiftUI to splice mismatched authority,
    /// semantics, or render generations.
    func energyRailAppProjection(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionEnergyRailAppProjection {
        let cockpit = cockpitSnapshot(
            atUptimeNanoseconds: now,
            scale: scale
        )
        let semantic = cockpit.energyRailPresentation
        let accessibility = cockpit.energyRailAccessibilityPresentation
        let render = energyRailRenderPresentation(
            atUptimeNanoseconds: now,
            scale: scale
        )
        let acceptedMeasurement = acceptedEnergyRailMeasurement(from: cockpit.measurement)

        guard semantic.identity == render.identity,
              semantic.identity == accessibility.identity,
              semantic.currentness == render.currentness,
              semantic.currentness == accessibility.currentness,
              equalOptionalFiniteNonnegative(semantic.acceptedWatts, render.acceptedWatts),
              equalOptionalFiniteNonnegative(semantic.acceptedWatts, accessibility.acceptedWatts),
              semantic.scaleOrigin == render.scaleOrigin else {
            return unavailableEnergyRailAppProjection(identity: semantic.identity)
        }

        switch semantic.currentness {
        case .live:
            guard let acceptedMeasurement,
                  acceptedMeasurement.identity == semantic.identity,
                  acceptedMeasurement.watts.isFinite,
                  acceptedMeasurement.watts >= 0,
                  semantic.acceptedWatts == acceptedMeasurement.watts,
                  accessibilityMatches(
                    acceptedMeasurement: acceptedMeasurement,
                    accessibility: accessibility
                  ) else {
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
                acceptedMeasurement: acceptedMeasurement,
                accessibilityPresentation: accessibility,
                displayWatts: validWatts(render.displayWatts) ?? acceptedMeasurement.watts,
                railFraction: validFraction(render.railFraction),
                acceptedTargetFraction: validFraction(semantic.acceptedTargetFraction),
                acceptedPeakMarkerFraction: validFraction(render.acceptedPeakMarkerFraction),
                scaleOrigin: semantic.scaleOrigin,
                allowsLiveMotion: motionAllowed
            )

        case .retained:
            guard let acceptedMeasurement,
                  acceptedMeasurement.identity == semantic.identity,
                  acceptedMeasurement.watts.isFinite,
                  acceptedMeasurement.watts >= 0,
                  semantic.acceptedWatts == acceptedMeasurement.watts,
                  accessibilityMatches(
                    acceptedMeasurement: acceptedMeasurement,
                    accessibility: accessibility
                  ) else {
                return unavailableEnergyRailAppProjection(identity: semantic.identity)
            }

            return PropulsionEnergyRailAppProjection(
                identity: semantic.identity,
                currentness: .retained,
                acceptedMeasurement: acceptedMeasurement,
                accessibilityPresentation: accessibility,
                displayWatts: acceptedMeasurement.watts,
                railFraction: nil,
                acceptedTargetFraction: nil,
                acceptedPeakMarkerFraction: nil,
                scaleOrigin: nil,
                allowsLiveMotion: false
            )

        case .unavailable:
            return unavailableEnergyRailAppProjection(identity: semantic.identity)
        }
    }

    private func acceptedEnergyRailMeasurement(
        from measurement: PropulsionGaugeCockpitMeasurement
    ) -> PropulsionGaugeCockpitAcceptedMeasurement? {
        switch measurement {
        case let .live(accepted), let .retained(accepted):
            return accepted
        case .unavailable:
            return nil
        }
    }

    private func accessibilityMatches(
        acceptedMeasurement: PropulsionGaugeCockpitAcceptedMeasurement,
        accessibility: PropulsionEnergyRailAccessibilityPresentation
    ) -> Bool {
        guard let revision = accessibility.acceptedRevision else { return false }
        return accessibility.acceptedWatts == acceptedMeasurement.watts
            && revision.authority == acceptedMeasurement.authority
            && revision.continuityGeneration == acceptedMeasurement.continuityGeneration
            && revision.receiptSequenceNumber == acceptedMeasurement.receiptSequenceNumber
            && revision.receivedAtUptimeNanoseconds == acceptedMeasurement.receivedAtUptimeNanoseconds
    }

    private func unavailableEnergyRailAppProjection(
        identity: PropulsionGaugeIdentity
    ) -> PropulsionEnergyRailAppProjection {
        PropulsionEnergyRailAppProjection(
            identity: identity,
            currentness: .unavailable,
            acceptedMeasurement: nil,
            accessibilityPresentation: .unavailable(identity: identity),
            displayWatts: nil,
            railFraction: nil,
            acceptedTargetFraction: nil,
            acceptedPeakMarkerFraction: nil,
            scaleOrigin: nil,
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