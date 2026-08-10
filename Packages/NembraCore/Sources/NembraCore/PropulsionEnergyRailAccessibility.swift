/// Accepted-measurement revision used by Energy Rail accessibility consumers.
///
/// This token advances only when the canonical cockpit accepts a different source
/// measurement. Display-clock interpolation and normalized rail geometry are
/// deliberately absent so a 60 Hz renderer cannot manufacture accessibility
/// updates or evidence from presentation frames.
///
/// This is measurement identity only. A freshness/currentness transition may
/// legitimately keep this value unchanged; accessibility consumers should key
/// semantic updates on `PropulsionEnergyRailAccessibilitySemanticRevision`.
public struct PropulsionEnergyRailAcceptedRevision: Equatable, Hashable, Sendable {
    public let authority: PropulsionPowerSampleAuthority
    public let continuityGeneration: UInt64
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64

    fileprivate init(
        authority: PropulsionPowerSampleAuthority,
        continuityGeneration: UInt64,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64
    ) {
        self.authority = authority
        self.continuityGeneration = continuityGeneration
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
    }
}

/// Complete cadence key for user-facing Energy Rail accessibility semantics.
///
/// Unlike `PropulsionEnergyRailAcceptedRevision`, this revision includes vehicle
/// identity and currentness. Therefore one accepted measurement becoming retained
/// (or unavailable) advances semantic state without pretending that a new physical
/// measurement arrived. Render-only geometry and interpolated display values remain
/// deliberately excluded.
public struct PropulsionEnergyRailAccessibilitySemanticRevision: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedRevision: PropulsionEnergyRailAcceptedRevision?

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedRevision: PropulsionEnergyRailAcceptedRevision?
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedRevision = acceptedRevision
    }
}

/// Stable semantic state for VoiceOver and other assistive technologies consuming
/// the Nembra Energy Rail.
///
/// `acceptedWatts` is always the exact newest accepted cockpit measurement. The
/// projection never exposes render-only rail fractions, interpolation values, peak
/// geometry, or a guessed zero. Retained evidence remains explicitly retained and
/// unavailable evidence carries no numeric value or accepted-measurement revision.
public struct PropulsionEnergyRailAccessibilityPresentation: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?
    public let acceptedRevision: PropulsionEnergyRailAcceptedRevision?
    public let semanticRevision: PropulsionEnergyRailAccessibilitySemanticRevision

    /// Module-internal construction keeps source-currentness transforms inside
    /// NembraCore. SwiftUI may consume this state but cannot synthesize it.
    init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedWatts: Double?,
        acceptedRevision: PropulsionEnergyRailAcceptedRevision?
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedWatts = acceptedWatts
        self.acceptedRevision = acceptedRevision
        self.semanticRevision = PropulsionEnergyRailAccessibilitySemanticRevision(
            identity: identity,
            currentness: currentness,
            acceptedRevision: acceptedRevision
        )
    }

    /// Package-internal fail-closed semantic state for projections that reject a
    /// mismatched render/semantic composition. Keeping construction here prevents
    /// an app adapter from having to synthesize accessibility currentness itself.
    static func unavailable(
        identity: PropulsionGaugeIdentity
    ) -> PropulsionEnergyRailAccessibilityPresentation {
        PropulsionEnergyRailAccessibilityPresentation(
            identity: identity,
            currentness: .unavailable,
            acceptedWatts: nil,
            acceptedRevision: nil
        )
    }
}

public extension PropulsionGaugeCockpitSnapshot {
    /// Projects Energy Rail accessibility semantics without coupling them to the
    /// display/render clock.
    ///
    /// A caller may evaluate this from every display frame. Equal accepted evidence
    /// at equal currentness produces an equal semantic revision even while the visual
    /// rail is interpolating. A meaningful freshness transition changes
    /// `semanticRevision` while preserving `acceptedRevision`, so VoiceOver can move
    /// from (for example) "640 watts" to "640 watts, last known" without claiming a
    /// new measurement. UI code should key semantic announcements on
    /// `semanticRevision`, never on 60 Hz rail geometry or `acceptedRevision` alone.
    var energyRailAccessibilityPresentation: PropulsionEnergyRailAccessibilityPresentation {
        switch measurement {
        case let .live(accepted):
            guard accepted.identity == identity else {
                return .unavailable(identity: identity)
            }
            return energyRailAccessibilityPresentation(
                accepted: accepted,
                currentness: .live
            )

        case let .retained(accepted):
            guard accepted.identity == identity else {
                return .unavailable(identity: identity)
            }
            return energyRailAccessibilityPresentation(
                accepted: accepted,
                currentness: .retained
            )

        case .unavailable:
            return .unavailable(identity: identity)
        }
    }

    private func energyRailAccessibilityPresentation(
        accepted: PropulsionGaugeCockpitAcceptedMeasurement,
        currentness: PropulsionEnergyRailCurrentness
    ) -> PropulsionEnergyRailAccessibilityPresentation {
        PropulsionEnergyRailAccessibilityPresentation(
            identity: identity,
            currentness: currentness,
            acceptedWatts: accepted.watts,
            acceptedRevision: PropulsionEnergyRailAcceptedRevision(
                authority: accepted.authority,
                continuityGeneration: accepted.continuityGeneration,
                receiptSequenceNumber: accepted.receiptSequenceNumber,
                receivedAtUptimeNanoseconds: accepted.receivedAtUptimeNanoseconds
            )
        )
    }
}