/// Accepted-measurement revision used by Energy Rail accessibility consumers.
///
/// This token advances only when the canonical cockpit accepts a different source
/// measurement. Display-clock interpolation and normalized rail geometry are
/// deliberately absent so a 60 Hz renderer cannot manufacture accessibility
/// updates or evidence from presentation frames.
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

/// Stable semantic state for VoiceOver and other assistive technologies consuming
/// the Nembra Energy Rail.
///
/// `acceptedWatts` is always the exact newest accepted cockpit measurement. The
/// projection never exposes render-only rail fractions, interpolation values, peak
/// geometry, or a guessed zero. Retained evidence remains explicitly retained and
/// unavailable evidence carries no numeric value or revision.
public struct PropulsionEnergyRailAccessibilityPresentation: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let currentness: PropulsionEnergyRailCurrentness
    public let acceptedWatts: Double?
    public let acceptedRevision: PropulsionEnergyRailAcceptedRevision?

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        currentness: PropulsionEnergyRailCurrentness,
        acceptedWatts: Double?,
        acceptedRevision: PropulsionEnergyRailAcceptedRevision?
    ) {
        self.identity = identity
        self.currentness = currentness
        self.acceptedWatts = acceptedWatts
        self.acceptedRevision = acceptedRevision
    }
}

public extension PropulsionGaugeCockpitSnapshot {
    /// Projects Energy Rail accessibility semantics at accepted-measurement cadence.
    ///
    /// A caller may evaluate this from every display frame, but equal accepted
    /// evidence produces an equal accessibility presentation even while the visual
    /// rail is interpolating. UI code can therefore key semantic announcements on
    /// `acceptedRevision` rather than on a 60 Hz render clock.
    var energyRailAccessibilityPresentation: PropulsionEnergyRailAccessibilityPresentation {
        switch measurement {
        case let .live(accepted):
            guard accepted.identity == identity else {
                return unavailableEnergyRailAccessibilityPresentation()
            }
            return energyRailAccessibilityPresentation(
                accepted: accepted,
                currentness: .live
            )

        case let .retained(accepted):
            guard accepted.identity == identity else {
                return unavailableEnergyRailAccessibilityPresentation()
            }
            return energyRailAccessibilityPresentation(
                accepted: accepted,
                currentness: .retained
            )

        case .unavailable:
            return unavailableEnergyRailAccessibilityPresentation()
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

    private func unavailableEnergyRailAccessibilityPresentation()
        -> PropulsionEnergyRailAccessibilityPresentation {
        PropulsionEnergyRailAccessibilityPresentation(
            identity: identity,
            currentness: .unavailable,
            acceptedWatts: nil,
            acceptedRevision: nil
        )
    }
}
