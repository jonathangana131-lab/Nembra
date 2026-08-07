public enum PropulsionGaugeCockpitPolicyError: Error, Equatable, Sendable {
    case invalidNearObservedCeilingFraction
}

/// Product-presentation policy only. The threshold decides when an already-qualified
/// observed-power scale may use near-maximum wording; it does not define or learn the scale.
public struct PropulsionGaugeCockpitPolicy: Equatable, Sendable {
    public let nearObservedCeilingFraction: Double

    public init(nearObservedCeilingFraction: Double) throws {
        guard nearObservedCeilingFraction.isFinite,
              nearObservedCeilingFraction > 0,
              nearObservedCeilingFraction <= 1 else {
            throw PropulsionGaugeCockpitPolicyError.invalidNearObservedCeilingFraction
        }
        self.nearObservedCeilingFraction = nearObservedCeilingFraction
    }
}

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

/// Whether near-observed-maximum product wording is currently justified.
///
/// Simulator QA receives its own case so synthetic calibration can exercise the visual state without
/// becoming authority for production wording. Verified wording is available only when both the accepted
/// measurement and the scale have already passed the canonical authority/identity admission boundary.
public enum PropulsionGaugeNearObservedCeilingStatus: Equatable, Sendable {
    case unavailable
    case belowThreshold
    case simulatorNearObservedCeiling
    case verifiedNearObservedCeiling
}

/// Cockpit-facing projection of the canonical propulsion gauge.
///
/// The projection deliberately does not expose `displayWatts`. The band position may move at display
/// refresh rate, while the numeric readout remains an accepted measurement (or explicitly retained /
/// unavailable). This prevents a SwiftUI cockpit from accidentally promoting interpolated frames into
/// physical telemetry simply by binding to the most convenient numeric property.
public struct PropulsionGaugeCockpitSnapshot: Equatable, Sendable {
    public let measurement: PropulsionGaugeCockpitMeasurement

    /// Render-only position for the live propulsion band. Never telemetry evidence.
    public let visualPropulsionFraction: Double?
    /// Render-only marker derived from accepted peak samples inside the canonical hold window.
    public let recentAcceptedPeakMarkerFraction: Double?
    /// Position of the newest accepted measurement inside the compatible observed presentation scale.
    /// Unlike `visualPropulsionFraction`, this value never follows display interpolation.
    public let acceptedObservedScaleFraction: Double?
    public let scaleOrigin: PropulsionGaugeScaleOrigin?
    public let nearObservedCeilingStatus: PropulsionGaugeNearObservedCeilingStatus

    fileprivate init(
        measurement: PropulsionGaugeCockpitMeasurement,
        visualPropulsionFraction: Double?,
        recentAcceptedPeakMarkerFraction: Double?,
        acceptedObservedScaleFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?,
        nearObservedCeilingStatus: PropulsionGaugeNearObservedCeilingStatus
    ) {
        self.measurement = measurement
        self.visualPropulsionFraction = visualPropulsionFraction
        self.recentAcceptedPeakMarkerFraction = recentAcceptedPeakMarkerFraction
        self.acceptedObservedScaleFraction = acceptedObservedScaleFraction
        self.scaleOrigin = scaleOrigin
        self.nearObservedCeilingStatus = nearObservedCeilingStatus
    }
}

public extension PropulsionGaugeDisplayModel {
    /// Projects one cockpit snapshot while keeping accepted-measurement truth and display-clock motion separate.
    func cockpitSnapshot(
        atUptimeNanoseconds now: UInt64,
        scale: PropulsionGaugeScale?,
        policy cockpitPolicy: PropulsionGaugeCockpitPolicy
    ) -> PropulsionGaugeCockpitSnapshot {
        let frame = frame(atUptimeNanoseconds: now, scale: scale)
        let accepted = accessibilitySnapshot(atUptimeNanoseconds: now, scale: scale)

        let measurement = cockpitMeasurement(from: accepted)

        // If the accepted projection itself cannot produce a usable measurement for what otherwise
        // looks like a live/retained frame, fail the whole cockpit surface closed rather than showing
        // moving presentation state with no accepted numeric truth behind it.
        guard measurement != .unavailable || accepted.availability == .unavailable else {
            return PropulsionGaugeCockpitSnapshot(
                measurement: .unavailable,
                visualPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                acceptedObservedScaleFraction: nil,
                scaleOrigin: nil,
                nearObservedCeilingStatus: .unavailable
            )
        }

        guard accepted.availability == .live else {
            return PropulsionGaugeCockpitSnapshot(
                measurement: measurement,
                visualPropulsionFraction: nil,
                recentAcceptedPeakMarkerFraction: nil,
                acceptedObservedScaleFraction: nil,
                scaleOrigin: nil,
                nearObservedCeilingStatus: .unavailable
            )
        }

        let acceptedFraction = accepted.acceptedObservedScaleFraction
        let scaleOrigin = accepted.scaleOrigin
        let nearObservedCeilingStatus = Self.nearObservedCeilingStatus(
            acceptedFraction: acceptedFraction,
            scaleOrigin: scaleOrigin,
            threshold: cockpitPolicy.nearObservedCeilingFraction
        )

        let hasCompatibleObservedScale = acceptedFraction != nil && scaleOrigin != nil

        return PropulsionGaugeCockpitSnapshot(
            measurement: measurement,
            visualPropulsionFraction: hasCompatibleObservedScale ? frame.normalizedPropulsion : nil,
            recentAcceptedPeakMarkerFraction: hasCompatibleObservedScale ? frame.acceptedPeakNormalized : nil,
            acceptedObservedScaleFraction: acceptedFraction,
            scaleOrigin: scaleOrigin,
            nearObservedCeilingStatus: nearObservedCeilingStatus
        )
    }

    private func cockpitMeasurement(
        from snapshot: PropulsionGaugeAccessibilitySnapshot
    ) -> PropulsionGaugeCockpitMeasurement {
        guard snapshot.availability != .unavailable,
              let watts = snapshot.latestAcceptedWatts,
              let receiptSequenceNumber = snapshot.latestAcceptedReceiptSequenceNumber,
              let receivedAtUptimeNanoseconds = snapshot.latestAcceptedUptimeNanoseconds,
              let authority = snapshot.latestAuthority else {
            return .unavailable
        }

        let accepted = PropulsionGaugeCockpitAcceptedMeasurement(
            watts: watts,
            receiptSequenceNumber: receiptSequenceNumber,
            receivedAtUptimeNanoseconds: receivedAtUptimeNanoseconds,
            authority: authority
        )

        switch snapshot.availability {
        case .live:
            return .live(accepted)
        case .retained:
            return .retained(accepted)
        case .unavailable:
            return .unavailable
        }
    }

    private static func nearObservedCeilingStatus(
        acceptedFraction: Double?,
        scaleOrigin: PropulsionGaugeScaleOrigin?,
        threshold: Double
    ) -> PropulsionGaugeNearObservedCeilingStatus {
        guard let acceptedFraction,
              let scaleOrigin else {
            return .unavailable
        }

        guard acceptedFraction >= threshold else {
            return .belowThreshold
        }

        switch scaleOrigin {
        case .simulator:
            return .simulatorNearObservedCeiling
        case .verifiedObservedEnvelope:
            return .verifiedNearObservedCeiling
        }
    }
}
