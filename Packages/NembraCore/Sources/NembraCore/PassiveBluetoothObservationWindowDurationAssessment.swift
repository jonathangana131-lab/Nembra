import Foundation

/// Fail-closed assessment of immutable passive-capture observation-window
/// duration evidence.
///
/// This type answers one deliberately narrow question: does the session contain
/// one unambiguous finite-acquisition-ready -> observation-horizon interval,
/// free of known byte-continuity breaks, whose monotonic duration meets the
/// caller-required minimum?
///
/// Every result retains the exact capture session identity and immutable vehicle
/// context that earned it so a legitimate assessment cannot be silently detached
/// from its source artifact across persistence, async, or UI boundaries. These
/// fields preserve declared source-session provenance; they are not a hash or
/// cryptographic binding of the raw capture bytes. Exact-byte binding belongs to
/// the capture/provenance artifact layer.
///
/// A sufficient result is Nembra lifecycle-duration evidence only. It does not
/// prove continuous BLE traffic, RF emission, foreground authority, target
/// identity, scooter health/state, protocol semantics, or physical hardware
/// behavior. Those remain separate acceptance gates.
public struct PassiveBluetoothObservationWindowDurationAssessment: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case sufficient
        case invalidMinimumDuration
        case missingFiniteAcquisitionReady
        case ambiguousFiniteAcquisitionReady
        case missingObservationHorizon
        case ambiguousObservationHorizon
        case horizonPrecedesReady
        case continuityBreakWithinWindow
        case insufficientDuration
    }

    /// Immutable source-capture provenance for this producer-derived assessment.
    public let captureSessionID: UUID
    public let vehicleIdentity: VehicleIdentity
    public let status: Status
    public let minimumRequiredDurationNanoseconds: UInt64
    public let observedDurationNanoseconds: UInt64?
    public let readyBoundary: PassiveBluetoothObservationBoundary?
    public let horizonBoundary: PassiveBluetoothObservationBoundary?
    /// Raw-record sequence numbers for known byte-continuity breaks strictly
    /// after readiness and at/before the terminal horizon watermark.
    public let continuityBreakSequenceNumbers: [UInt64]

    /// Convenience only; this explicitly names duration sufficiency so callers
    /// do not accidentally treat it as proof that the whole physical capture
    /// experiment is accepted.
    public var isDurationSufficient: Bool {
        status == .sufficient
    }

    private init(
        captureSessionID: UUID,
        vehicleIdentity: VehicleIdentity,
        status: Status,
        minimumRequiredDurationNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64?,
        readyBoundary: PassiveBluetoothObservationBoundary?,
        horizonBoundary: PassiveBluetoothObservationBoundary?,
        continuityBreakSequenceNumbers: [UInt64] = []
    ) {
        self.captureSessionID = captureSessionID
        self.vehicleIdentity = vehicleIdentity
        self.status = status
        self.minimumRequiredDurationNanoseconds = minimumRequiredDurationNanoseconds
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.readyBoundary = readyBoundary
        self.horizonBoundary = horizonBoundary
        self.continuityBreakSequenceNumbers = continuityBreakSequenceNumbers
    }

    private static func result(
        for session: PassiveBluetoothCaptureSession,
        status: Status,
        minimumRequiredDurationNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64?,
        readyBoundary: PassiveBluetoothObservationBoundary?,
        horizonBoundary: PassiveBluetoothObservationBoundary?,
        continuityBreakSequenceNumbers: [UInt64] = []
    ) -> Self {
        Self(
            captureSessionID: session.id,
            vehicleIdentity: session.vehicleIdentity,
            status: status,
            minimumRequiredDurationNanoseconds: minimumRequiredDurationNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds,
            readyBoundary: readyBoundary,
            horizonBoundary: horizonBoundary,
            continuityBreakSequenceNumbers: continuityBreakSequenceNumbers
        )
    }

    /// Assesses a caller-defined minimum using the capture's monotonic uptime
    /// clock and complete ordered raw-record/boundary evidence. Wall-clock
    /// `Date` values are intentionally ignored for duration authority.
    ///
    /// This evaluator never guesses among duplicate/nested ready boundaries.
    /// Exactly one ready and one horizon are required. Any raw event whose
    /// domain semantics break byte continuity inside that interval also blocks
    /// sufficiency, even when the elapsed uptime exceeds the requested minimum.
    ///
    /// A zero minimum fails closed so an accidentally unconfigured product gate
    /// cannot silently accept an empty observation window.
    public static func assess(
        session: PassiveBluetoothCaptureSession,
        minimumDurationNanoseconds: UInt64
    ) -> Self {
        let readyMatches = session.observationBoundaries.enumerated().filter {
            $0.element.kind == .finiteAcquisitionReady
        }
        let horizonMatches = session.observationBoundaries.enumerated().filter {
            $0.element.kind == .observationHorizon
        }

        guard minimumDurationNanoseconds > 0 else {
            return result(
                for: session,
                status: .invalidMinimumDuration,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyMatches.count == 1 ? readyMatches[0].element : nil,
                horizonBoundary: horizonMatches.count == 1 ? horizonMatches[0].element : nil
            )
        }

        guard !readyMatches.isEmpty else {
            return result(
                for: session,
                status: .missingFiniteAcquisitionReady,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: nil,
                horizonBoundary: horizonMatches.count == 1 ? horizonMatches[0].element : nil
            )
        }
        guard readyMatches.count == 1 else {
            return result(
                for: session,
                status: .ambiguousFiniteAcquisitionReady,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: nil,
                horizonBoundary: horizonMatches.count == 1 ? horizonMatches[0].element : nil
            )
        }
        guard !horizonMatches.isEmpty else {
            return result(
                for: session,
                status: .missingObservationHorizon,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyMatches[0].element,
                horizonBoundary: nil
            )
        }
        guard horizonMatches.count == 1 else {
            return result(
                for: session,
                status: .ambiguousObservationHorizon,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyMatches[0].element,
                horizonBoundary: nil
            )
        }

        let readyMatch = readyMatches[0]
        let horizonMatch = horizonMatches[0]
        let readyBoundary = readyMatch.element
        let horizonBoundary = horizonMatch.element

        guard horizonMatch.offset > readyMatch.offset,
              horizonBoundary.recordSequenceWatermark >= readyBoundary.recordSequenceWatermark,
              horizonBoundary.observedAtUptimeNanoseconds >= readyBoundary.observedAtUptimeNanoseconds else {
            return result(
                for: session,
                status: .horizonPrecedesReady,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundary: readyBoundary,
                horizonBoundary: horizonBoundary
            )
        }

        let observedDurationNanoseconds =
            horizonBoundary.observedAtUptimeNanoseconds - readyBoundary.observedAtUptimeNanoseconds
        let continuityBreakSequenceNumbers = session.records.compactMap { record -> UInt64? in
            guard record.sequenceNumber > readyBoundary.recordSequenceWatermark,
                  record.sequenceNumber <= horizonBoundary.recordSequenceWatermark,
                  record.event.breaksByteContinuity else {
                return nil
            }
            return record.sequenceNumber
        }

        guard continuityBreakSequenceNumbers.isEmpty else {
            return result(
                for: session,
                status: .continuityBreakWithinWindow,
                minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
                observedDurationNanoseconds: observedDurationNanoseconds,
                readyBoundary: readyBoundary,
                horizonBoundary: horizonBoundary,
                continuityBreakSequenceNumbers: continuityBreakSequenceNumbers
            )
        }

        let status: Status = observedDurationNanoseconds >= minimumDurationNanoseconds
            ? .sufficient
            : .insufficientDuration

        return result(
            for: session,
            status: status,
            minimumRequiredDurationNanoseconds: minimumDurationNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds,
            readyBoundary: readyBoundary,
            horizonBoundary: horizonBoundary
        )
    }
}
