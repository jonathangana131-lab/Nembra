import Foundation

public enum PropulsionObservedScaleRegionPolicyError: Error, Equatable, Sendable {
    case invalidNearEdgeFraction
}

/// Product-presentation policy for deciding when one *accepted* power measurement
/// sits near the edge of a compatible learned observed-power gauge scale.
///
/// This threshold is a presentation choice only. It does not define full throttle,
/// rated power, motor load, or a physical maximum. It may be deliberately loose
/// for Simulator QA or visual experimentation and therefore is never sufficient
/// by itself to authorize wording that implies proximity to an observed maximum.
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

/// Product-owned language policy for verified wording such as "Near observed max".
///
/// This intentionally cannot be constructed with an arbitrary caller-supplied
/// fraction. Changing the wording boundary requires an explicit Nembra source
/// change/review rather than silently weakening semantic language through a
/// generic visual-region configuration.
///
/// The fraction is relative to a compatible learned *presentation* scale. It is
/// not an AOVOPRO ES80 physical threshold, rated/certified power percentage,
/// throttle position, motor load, or proof of a perfect continuous-time maximum.
public struct PropulsionVerifiedNearObservedMaximumWordingPolicy: Equatable, Sendable {
    public static let product = Self(minimumObservedScaleFraction: 0.9)

    public let minimumObservedScaleFraction: Double

    private init(minimumObservedScaleFraction: Double) {
        self.minimumObservedScaleFraction = minimumObservedScaleFraction
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
    /// "Near observed max". It requires the configurable semantic visual region,
    /// a current accepted verified-vehicle power measurement, a compatible
    /// verified observed-envelope presentation scale, and the independent
    /// product-owned wording floor.
    ///
    /// The separate wording floor prevents a caller from choosing an arbitrarily
    /// low visual threshold (for example `0.01`) and thereby making 1% of the
    /// learned presentation scale eligible for near-maximum language. It still
    /// does not mean throttle position, rated/certified maximum, or a perfect
    /// continuous-time physical maximum.
    public var permitsVerifiedNearObservedMaximumWording: Bool {
        guard region == .nearObservedScaleEdge,
              availability == .live,
              latestAuthority == .verifiedVehicleMeasurement,
              scaleOrigin == .verifiedObservedEnvelope,
              let acceptedFraction = acceptedObservedScaleFraction,
              acceptedFraction.isFinite,
              acceptedFraction >= 0,
              acceptedFraction <= 1,
              acceptedFraction >= PropulsionVerifiedNearObservedMaximumWordingPolicy.product.minimumObservedScaleFraction else {
            return false
        }
        return true
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
