/// The accepted numeric power value that a cockpit may present as a measurement.
/// Construction is file-private so callers cannot relabel an interpolated render value as accepted evidence.
public struct PropulsionGaugeCockpitAcceptedMeasurement: Equatable, Sendable {
    public let watts: Double
    public let receiptSequenceNumber: UInt64
    public let receivedAtUptimeNanoseconds: UInt64
    public let authority: PropulsionPowerSampleAuthority

    fileprivate init(
        watts: Double,
        receiptSequenceNumber: UInt64,
        receivedAtUptimeNanoseconds: UInt64,
        authority: PropulsionPowerSampleAuthority
    ) {
        self.watts = watts
        self.receiptSequenceNumber = receiptSequenceNumber
        self.receivedAtUptimeNanoseconds = receivedAtUptimeNanoseconds
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
    public let measurement: PropulsionGaugeCockpitMeasurement

    /// Render-only position for the live propulsion band. Never telemetry evidence.
    public let visualPropulsionFraction: Double?
    /// Render-only marker derived from accepted peak samples inside the canonical hold window.
    public let recentAcceptedPeakMarkerFraction: Double?
    /// The compatible presentation-scale origin admitted by the canonical gauge frame.
    /// This is presentation provenance only; it does not convert render fractions into measurements.
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    fileprivate init(
        measurement: PropulsionGaugeCockpitMeasurement,
        visualPropulsionFraction: Double?,
        recentAcceptedPeakMarkerFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?
    ) {
        self.measurement = measurement
        self.visualPropulsionFraction = visualPropulsionFraction
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
        cockpitSnapshot(
            from: frame(atUptimeNanoseconds: now, scale: scale)
        )
    }

    /// Internal composition seam for callers that already evaluated the canonical
    /// gauge frame for this display tick. This keeps the cockpit's numeric truth
    /// and render-only motion on one presentation cut without re-running display
    /// interpolation.
    internal func cockpitSnapshot(
        from frame: PropulsionGaugeFrame
    ) -> PropulsionGaugeCockpitSnapshot {
        let measurement = cockpitMeasurement(from: frame)

        // A live/retained frame must carry complete accepted provenance. If it does not, fail the whole
        // cockpit surface closed rather than showing moving presentation state without accepted truth.
        guard measurement != .unavailable || frame.availability == .unavailable else {
            return PropulsionGaugeCockpitSnapshot(
                measurement: .unavailable,
                visualPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        guard frame.availability == .live else {
            return PropulsionGaugeCockpitSnapshot(
                measurement: measurement,
                visualPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                scaleOrigin: nil
            )
        }

        return PropulsionGaugeCockpitSnapshot(
            measurement: measurement,
            visualPropulsionFraction: frame.normalizedPropulsion,
            recentAcceptedPeakMarkerFraction: frame.acceptedPeakNormalized,
            scaleOrigin: frame.scaleOrigin
        )
    }

    private func cockpitMeasurement(
        from frame: PropulsionGaugeFrame
    ) -> PropulsionGaugeCockpitMeasurement {
        guard frame.availability != .unavailable,
              let watts = frame.latestAcceptedWatts,
              let receiptSequenceNumber = frame.latestAcceptedReceiptSequenceNumber,
              let receivedAtUptimeNanoseconds = frame.latestAcceptedUptimeNanoseconds,
              let authority = frame.latestAuthority else {
            return .unavailable
        }

        let accepted = PropulsionGaugeCockpitAcceptedMeasurement(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
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