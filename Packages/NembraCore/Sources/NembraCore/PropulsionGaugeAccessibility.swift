/// Accessibility-facing projection of the propulsion gauge.
///
/// This snapshot deliberately contains no display-clock/interpolated watt value.
/// Assistive technologies should announce the newest accepted measurement, not a
/// transient render frame between measurements.
public struct PropulsionGaugeAccessibilitySnapshot: Equatable, Sendable {
    public let availability: PropulsionGaugeAvailability
    public let latestAcceptedWatts: Double?
    public let latestAcceptedUptimeNanoseconds: UInt64?
    public let latestAuthority: PropulsionPowerSampleAuthority?

    /// Position of the newest accepted measurement within a compatible observed
    /// presentation scale. This is not throttle position, motor load percentage,
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
        latestAcceptedUptimeNanoseconds: UInt64?,
        latestAuthority: PropulsionPowerSampleAuthority?,
        acceptedObservedScaleFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?
    ) {
        self.availability = availability
        self.latestAcceptedWatts = latestAcceptedWatts
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
    /// reported watts remain pinned to `latestAcceptedWatts`. Render-only
    /// interpolation therefore cannot leak into VoiceOver values, persistence,
    /// statistics, calibration, or any other evidence path.
    func accessibilitySnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?
    ) -> PropulsionGaugeAccessibilitySnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)

        guard frame.availability == .live,
              let latestAcceptedWatts = frame.latestAcceptedWatts,
              let latestAuthority = frame.latestAuthority,
              let compatibleScale = compatibleAccessibilityScale(
                scale,
                authority: latestAuthority
              ) else {
            return PropulsionGaugeAccessibilitySnapshot(
                availability: frame.availability,
                latestAcceptedWatts: frame.latestAcceptedWatts,
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
            latestAcceptedUptimeNanoseconds: frame.latestAcceptedUptimeNanoseconds,
            latestAuthority: latestAuthority,
            acceptedObservedScaleFraction: acceptedFraction,
            scaleOrigin: compatibleScale.origin
        )
    }

    private func compatibleAccessibilityScale(
        _ scale: PropulsionGaugeScale?,
        authority: PropulsionPowerSampleAuthority
    ) -> PropulsionGaugeScale? {
        guard let scale, scale.identity == identity else {
            return nil
        }

        switch (scale.origin, authority) {
        case (.verifiedObservedEnvelope, .verifiedVehicleMeasurement),
             (.simulator, .simulator):
            return scale
        default:
            return nil
        }
    }
}
