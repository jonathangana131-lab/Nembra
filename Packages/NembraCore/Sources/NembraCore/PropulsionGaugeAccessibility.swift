/// Accessibility-facing projection of the propulsion gauge.
///
/// This snapshot deliberately contains no display-clock/interpolated watt value.
/// Assistive technologies should announce the newest accepted measurement, not a
/// transient render frame between measurements.
public struct PropulsionGaugeAccessibilitySnapshot: Equatable, Sendable {
    public let availability: PropulsionGaugeAvailability
    public let latestAcceptedWatts: Double?
    public let latestAcceptedReceiptSequenceNumber: UInt64?
    public let latestAcceptedUptimeNanoseconds: UInt64?
    public let latestAuthority: PropulsionPowerSampleAuthority?

    /// Position of the newest accepted measurement within a compatible observed
    /// presentation scale. This is not throttle position, motor-load percentage,
    /// rated-power percentage, or a new telemetry sample.
    ///
    /// It is intentionally unavailable when evidence is retained/stale,
    /// explicitly unavailable, or when the supplied scale does not match the
    /// measurement's vehicle/mode identity and authority.
    public let acceptedObservedScaleFraction: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    fileprivate init(
        availability: PropulsionGaugeAvailability,
        latestAcceptedWatts: Double?,
        latestAcceptedReceiptSequenceNumber: UInt64?,
        latestAcceptedUptimeNanoseconds: UInt64?,
        latestAuthority: PropulsionPowerSampleAuthority?,
        acceptedObservedScaleFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?
    ) {
        self.availability = availability
        self.latestAcceptedWatts = latestAcceptedWatts
        self.latestAcceptedReceiptSequenceNumber = latestAcceptedReceiptSequenceNumber
        self.latestAcceptedUptimeNanoseconds = latestAcceptedUptimeNanoseconds
        self.latestAuthority = latestAuthority
        self.acceptedObservedScaleFraction = acceptedObservedScaleFraction
        self.scaleOrigin = scaleOrigin
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Projects stable accessibility semantics from the same accepted propulsion
    /// evidence that drives the visual gauge.
    ///
    /// Callers may request this snapshot at display refresh rate, but the
    /// reported watts and receipt provenance remain pinned to the newest accepted
    /// measurement. Render-only interpolation therefore cannot leak into
    /// VoiceOver values, persistence, statistics, calibration, or any other
    /// evidence path.
    func accessibilitySnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeAccessibilitySnapshot {
        accessibilitySnapshot(
            from: frame(atUptimeNanoseconds: now, scale: scale),
            scale: scale
        )
    }

    /// Internal composition seam for callers that already evaluated the canonical
    /// gauge frame for this display tick. Reusing that exact frame keeps visual,
    /// semantic, and accessibility projections on one immutable presentation cut
    /// without turning render interpolation into accepted evidence.
    internal func accessibilitySnapshot(
        from frame: PropulsionGaugeFrame,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeAccessibilitySnapshot {
        // The accepted presentation frame remains the single authority for scale
        // compatibility. Accessibility must not duplicate vehicle/mode/authority
        // admission rules that could later diverge from the visual model.
        guard frame.availability == .live,
              let latestAcceptedWatts = frame.latestAcceptedWatts,
              let compatibleScale = scale,
              let scaleOrigin = frame.scaleOrigin,
              compatibleScale.origin == scaleOrigin else {
            return PropulsionGaugeAccessibilitySnapshot(
                availability: frame.availability,
                latestAcceptedWatts: frame.latestAcceptedWatts,
                latestAcceptedReceiptSequenceNumber: frame.latestAcceptedReceiptSequenceNumber,
                latestAcceptedUptimeNanoseconds: frame.latestAcceptedUptimeNanoseconds,
                latestAuthority: frame.latestAuthority,
                acceptedObservedScaleFraction: nil,
                scaleOrigin: nil
            )
        }

        let acceptedFraction = min(
            1,
            max(0, latestAcceptedWatts / compatibleScale.ceilingWatts)
        )

        return PropulsionGaugeAccessibilitySnapshot(
            availability: frame.availability,
            latestAcceptedWatts: latestAcceptedWatts,
            latestAcceptedReceiptSequenceNumber: frame.latestAcceptedReceiptSequenceNumber,
            latestAcceptedUptimeNanoseconds: frame.latestAcceptedUptimeNanoseconds,
            latestAuthority: frame.latestAuthority,
            acceptedObservedScaleFraction: acceptedFraction,
            scaleOrigin: scaleOrigin
        )
    }
}