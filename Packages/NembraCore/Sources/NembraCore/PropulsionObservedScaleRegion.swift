import Foundation

public enum PropulsionObservedScaleRegionPolicyError: Error, Equatable, Sendable {
    case invalidNearEdgeFraction
}

/// Product-presentation policy for deciding when one *accepted* power measurement
/// sits near the edge of a compatible learned observed-power gauge scale.
///
/// This threshold is a presentation choice only. It does not define full throttle,
/// rated power, motor load, or a physical maximum.
public struct PropulsionObservedScaleRegionPolicy: Equatable, Sendable {
    public let nearEdgeFraction: Double

    public init(nearEdgeFraction: Double) throws {
        guard nearEdgeFraction.isFinite,
              nearEdgeFraction > 0,
              nearEdgeFraction <= 1 else {
            throw PropulsionObservedScaleRegionPolicyError.invalidNearEdgeFraction
        }
        self.nearEdgeFraction = nearEdgeFraction
    }
}

/// Render-independent semantic region for the current accepted propulsion sample.
///
/// A future cockpit may use `.nearObservedScaleEdge` for restrained emphasis or
/// truthful wording such as "near observed max". It must not relabel this state as
/// throttle position, rated/certified maximum, or a new telemetry measurement.
public enum PropulsionObservedScaleRegion: String, Equatable, Sendable {
    case unavailable
    case retained
    case observedScaleUnavailable
    case normal
    case nearObservedScaleEdge
}

/// Product-facing projection that remains pinned to the measurement clock even
/// while the visual propulsion gauge animates at display refresh rate.
public struct PropulsionObservedScaleRegionSnapshot: Equatable, Sendable {
    public let region: PropulsionObservedScaleRegion
    public let availability: PropulsionGaugeAvailability
    public let latestAcceptedWatts: Double?
    public let latestAcceptedReceiptSequenceNumber: UInt64?
    public let latestAcceptedUptimeNanoseconds: UInt64?
    public let latestAuthority: PropulsionPowerSampleAuthority?
    public let acceptedObservedScaleFraction: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?

    public var isNearObservedScaleEdge: Bool {
        region == .nearObservedScaleEdge
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Projects a stable observed-scale region from the same accepted-only
    /// accessibility snapshot used to keep VoiceOver off interpolated frames.
    ///
    /// Calling this every display frame is safe: render-only gauge motion can
    /// never enter or leave the semantic near-edge region by itself.
    func observedScaleRegionSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        policy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionObservedScaleRegionSnapshot {
        let accepted = accessibilitySnapshot(
            atUptimeNanoseconds: now,
            scale: scale
        )

        let region: PropulsionObservedScaleRegion
        switch accepted.availability {
        case .unavailable:
            region = .unavailable
        case .retained:
            region = .retained
        case .live:
            guard let acceptedFraction = accepted.acceptedObservedScaleFraction,
                  acceptedFraction.isFinite,
                  accepted.scaleOrigin != nil else {
                region = .observedScaleUnavailable
                return PropulsionObservedScaleRegionSnapshot(
                    region: region,
                    availability: accepted.availability,
                    latestAcceptedWatts: accepted.latestAcceptedWatts,
                    latestAcceptedReceiptSequenceNumber: accepted.latestAcceptedReceiptSequenceNumber,
                    latestAcceptedUptimeNanoseconds: accepted.latestAcceptedUptimeNanoseconds,
                    latestAuthority: accepted.latestAuthority,
                    acceptedObservedScaleFraction: nil,
                    scaleOrigin: nil
                )
            }
            region = acceptedFraction >= policy.nearEdgeFraction
                ? .nearObservedScaleEdge
                : .normal
        }

        return PropulsionObservedScaleRegionSnapshot(
            region: region,
            availability: accepted.availability,
            latestAcceptedWatts: accepted.latestAcceptedWatts,
            latestAcceptedReceiptSequenceNumber: accepted.latestAcceptedReceiptSequenceNumber,
            latestAcceptedUptimeNanoseconds: accepted.latestAcceptedUptimeNanoseconds,
            latestAuthority: accepted.latestAuthority,
            acceptedObservedScaleFraction: accepted.acceptedObservedScaleFraction,
            scaleOrigin: accepted.scaleOrigin
        )
    }
}
