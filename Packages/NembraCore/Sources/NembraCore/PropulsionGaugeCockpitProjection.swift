/// The accepted numeric power value that a cockpit may present as a measurement.
/// Construction is file-private so callers cannot relabel an interpolated render value as accepted evidence.
public struct PropulsionGaugeCockpitAcceptedMeasurement: Equatable, Sendable {
    /// Exact vehicle/mode identity of the display model that accepted this measurement.
    /// Detached cockpit values must stay bound to their source identity rather than relying on
    /// whichever vehicle happens to be current when a UI callback is later delivered.
    public let identity: PropulsionGaugeIdentity
    public let watts: Double
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    /// Source continuity/clock generation of this accepted measurement. A newer generation may
    /// legitimately restart receipt sequence and uptime, so detached measurements must preserve it.
    public let continuityGeneration: UInt64
    public let authority: PropulsionPowerSampleAuthority

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) {
        self.identity = identity
        self.watts = watts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
        self.continuityGeneration = continuityGeneration
        self.authority = authority
    }
}

/// Numeric cockpit truth is intentionally typed by currentness. `.retained` is last accepted
/// evidence, not a fresh measurement; `.unavailable` carries no primary numeric value.
public enum PropulsionGaugeCockpitMeasurement: Equatable, Sendable {
    case live(PropulsionGaugeCockpitAcceptedMeasurement)
    case retained(PropulsionGaugeCockpitAcceptedMeasurement)
    case unavailable
}

/// Cockpit-facing projection of the canonical propulsion gauge.
///
/// This type deliberately does not expose `displayWatts`. The band may move at display refresh rate,
/// while the numeric readout remains tied to an accepted measurement (or explicitly retained /
/// unavailable). Product semantics such as "near observed max" are intentionally owned by the separate
/// accepted-power observed-scale-region layer rather than duplicated here.
public struct PropulsionGaugeCockpitSnapshot: Equatable, Sendable {
    public let identity: PropulsionGaugeIdentity
    public let measurement: PropulsionGaugeCockpitMeasurement
    public let visualPropulsionFraction: Double?
    public let acceptedPropulsionFraction: Double?
    public let recentAcceptedPeakMarkerFraction: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    fileprivate init(
        identity: PropulsionGaugeIdentity,
        measurement: PropulsionGaugeCockpitMeasurement,
        visualPropulsionFraction: Double?,
        acceptedPropulsionFraction: Double?,
        recentAcceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?
    ) {
        self.identity = identity
        self.measurement = measurement
        self.visualPropulsionFraction = visualPropulsionFraction
        self.acceptedPropulsionFraction = acceptedPropulsionFraction
        self.recentAcceptedPeakMarkerFraction = recentAcceptedPeakMarkerFraction
        self.scaleOrigin = scaleOrigin
    }

#if SWIFT_PACKAGE
    /// Package-sealed reconstruction of an exact source-owned Simulator receipt as
    /// retained cockpit truth. This supports a fresh runtime/view mount after source
    /// custody already demoted a legitimate receipt. It never creates live geometry,
    /// a local receipt, or a render-clock timestamp.
    package static func retainedSimulatorSource(
        identity: PropulsionGaugeIdentity,
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        continuityGeneration: UInt64
    ) -> Self? {
        guard watts.isFinite,
              watts >= 0,
              receiptSequenceNumber > 0,
              receivedAtUptimeNanoseconds > 0,
              continuityGeneration > 0 else {
            return nil
        }

        let accepted = PropulsionGaugeCockpitAcceptedMeasurement(
            identity: identity,
            watts: watts == 0 ? 0 : watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: .simulator
        )
        return Self(
            identity: identity,
            measurement: .retained(accepted),
            visualPropulsionFraction: nil,
            acceptedPropulsionFraction: nil,
            recentAcceptedPeakMarkerFraction: nil,
            scaleOrigin: nil
        )
    }
#endif
}

public extension PropulsionGaugeDisplayModel {
    func cockpitSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeCockpitSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let measurement = cockpitMeasurement(from: frame)

        guard measurement != .unavailable || frame.availability == .unavailable else {
            return PropulsionGaugeCockpitSnapshot(
                identity: frame.identity,
                measurement: .unavailable,
                visualPropulsionFraction: nil,
                acceptedPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        guard frame.availability == .live else {
            return PropulsionGaugeCockpitSnapshot(
                identity: frame.identity,
                measurement: measurement,
                visualPropulsionFraction: nil,
                acceptedPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        return PropulsionGaugeCockpitSnapshot(
            identity: frame.identity,
            measurement: measurement,
            visualPropulsionFraction: frame.normalizedPropulsion,
            acceptedPropulsionFraction: acceptedPropulsionFraction(
                from: measurement,
                scale: scale,
                admittedScaleOrigin: frame.scaleOrigin
            ),
            recentAcceptedPeakMarkerFraction: frame.acceptedPeakNormalized,
            scaleOrigin: frame.scaleOrigin
        )
    }

    private func acceptedPropulsionFraction(
        from measurement: PropulsionGaugeCockpitMeasurement,
        scale: PropulsionGaugeScale?,
        admittedScaleOrigin: PropulsionGaugeScaleOrigin?
    ) -> Double? {
        guard case let .live(accepted) = measurement,
              let scale,
              let admittedScaleOrigin,
              accepted.identity == identity,
              accepted.watts.isFinite,
              accepted.watts >= 0,
              scale.identity == identity,
              scale.origin == admittedScaleOrigin,
              scale.ceilingWatts.isFinite,
              scale.ceilingWatts > 0 else {
            return nil
        }

        let fraction = accepted.watts / scale.ceilingWatts
        guard fraction.isFinite else { return nil }
        return min(1, max(0, fraction))
    }

    private func cockpitMeasurement(
        from frame: PropulsionGaugeFrame
    ) -> PropulsionGaugeCockpitMeasurement {
        guard frame.availability != .unavailable,
              let watts = frame.latestAcceptedWatts,
              let receiptSequenceNumber = frame.latestAcceptedReceiptSequenceNumber,
              let receivedAtUptimeNanoseconds = frame.latestAcceptedUptimeNanoseconds,
              let continuityGeneration = frame.latestAcceptedContinuityGeneration,
              let authority = frame.latestAuthority else {
            return .unavailable
        }

        let accepted = PropulsionGaugeCockpitAcceptedMeasurement(
            identity: frame.identity,
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            continuityGeneration: continuityGeneration,
            authority: authority
        )

        switch frame.availability {
        case .live:
            return .live(accepted)
        case .retained:
            return .retained(accepted)
        case .unavailable:
            return .unavailable
        }
    }
}
