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
    /// Exact vehicle/mode identity for this snapshot, including unavailable states.
    /// Keeping identity on the snapshot prevents an asynchronous/cached projection from becoming
    /// ordinary-looking state for a different selected vehicle or confirmed mode.
    public let identity: PropulsionGaugeIdentity
    public let measurement: PropulsionGaugeCockpitMeasurement

    /// Render-only position for the live propulsion band. Never telemetry evidence.
    public let visualPropulsionFraction: Double?
    /// Display-only normalization of the exact latest accepted watts against the same compatible
    /// presentation scale admitted by this snapshot. Unlike `visualPropulsionFraction`, this value
    /// does not move between display frames for one accepted measurement. It exists so Reduce Motion
    /// consumers can snap to the accepted target without re-normalizing truth or using interpolation.
    /// It remains presentation geometry and must never be persisted or promoted to telemetry evidence.
    public let acceptedPropulsionFraction: Double?
    /// Render-only marker derived from accepted peak samples inside the canonical hold window.
    public let recentAcceptedPeakMarkerFraction: Double?
    /// The compatible presentation-scale origin admitted by the canonical gauge frame.
    /// This is presentation provenance only; it does not convert render fractions into measurements.
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
}

public extension PropulsionGaugeDisplayModel {
    /// Projects one cockpit snapshot while keeping accepted-measurement truth and display-clock motion separate.
    /// The canonical frame is evaluated exactly once per call so a 60 Hz cockpit does not duplicate
    /// interpolation work merely to recover the accepted numeric value.
    func cockpitSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeCockpitSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let measurement = cockpitMeasurement(from: frame)

        // A live/retained frame must carry complete accepted provenance. If it does not, fail the whole
        // cockpit surface closed rather than showing moving presentation state without accepted truth.
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
            acceptedPropulsionFraction: acceptedPropulsionFraction(from: frame, scale: scale),
            recentAcceptedPeakMarkerFraction: frame.acceptedPeakNormalized,
            scaleOrigin: frame.scaleOrigin
        )
    }

    /// Produces stable display geometry for the exact accepted target only when the canonical frame
    /// admitted the caller's scale for this identity/authority pair. This deliberately does not
    /// reconstruct a measurement from geometry: accepted watts remain the sole numeric truth.
    private func acceptedPropulsionFraction(
        from frame: PropulsionGaugeFrame,
        scale: PropulsionGaugeScale?
    ) -> Double? {
        guard let admittedScaleOrigin = frame.scaleOrigin,
              let scale,
              admittedScaleOrigin == scale.origin,
              scale.identity == frame.identity,
              let acceptedWatts = frame.latestAcceptedWatts else {
            return nil
        }

        return min(1, max(0, acceptedWatts / scale.ceilingWatts))
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
