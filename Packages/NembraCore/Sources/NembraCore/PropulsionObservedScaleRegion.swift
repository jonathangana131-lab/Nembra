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
/// `.nearObservedScaleEdge` remains authority-agnostic so Simulator QA can exercise
/// the same visual region. Product wording must use the snapshot's verified wording
/// eligibility instead of treating this enum case alone as physical evidence.
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

    /// Visual-region convenience only. This may be true for Simulator QA and must
    /// not by itself drive production wording that implies physically verified
    /// observed-power authority.
    public var isNearObservedScaleEdge: Bool {
        region == .nearObservedScaleEdge
    }

    /// The only convenience intended to gate production wording such as
    /// "Near observed max". It requires the semantic region, a current accepted
    /// verified-vehicle power measurement, and a compatible verified observed-
    /// envelope presentation scale. It still does not mean throttle position,
    /// rated/certified maximum, or a perfect continuous-time physical maximum.
    public var permitsVerifiedNearObservedMaximumWording: Bool {
        region == .nearObservedScaleEdge
            && availability == .live
            && latestAuthority == .verifiedVehicleMeasurement
            && scaleOrigin == .verifiedObservedEnvelope
    }

    /// Explicit Simulator-QA classification so visual tests can exercise the
    /// region without accidentally sharing the production verified-wording gate.
    public var isSimulatorNearObservedScaleEdge: Bool {
        region == .nearObservedScaleEdge
            && availability == .live
            && latestAuthority == .simulator
            && scaleOrigin == .simulator
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Projects a stable observed-scale region from the same accepted-only
    /// evidence used to keep VoiceOver off interpolated frames.
    ///
    /// Calling this every display frame is safe: render-only gauge motion can
    /// never enter or leave the semantic near-edge region by itself.
    func observedScaleRegionSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        policy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionObservedScaleRegionSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let accepted = accessibilitySnapshot(from: frame, scale: scale)
        return observedScaleRegionSnapshot(from: accepted, policy: policy)
    }
}

extension PropulsionGaugeDisplayModel {
    /// Internal semantic projection from accepted-only evidence. Higher-level
    /// cockpit composition can provide an accessibility snapshot derived from the
    /// same canonical frame used for render motion, avoiding a second frame pass
    /// without weakening the accepted-measurement boundary.
    func observedScaleRegionSnapshot(
        from accepted: PropulsionGaugeAccessibilitySnapshot,
        policy: PropulsionObservedScaleRegionPolicy
    ) -> PropulsionObservedScaleRegionSnapshot {
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
                return PropulsionObservedScaleRegionSnapshot(
                    region: .observedScaleUnavailable,
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