import NembraCore

/// Validation errors for caller-owned observation-window policy.
///
/// The minimum duration is product/experiment policy, not a Bluetooth cadence,
/// scooter timing constant, or physical AOVOPRO ES80 property. This layer keeps
/// that policy explicit rather than silently embedding a hardware-looking
/// default into a generic evidence assessor.
public enum PassiveBluetoothObservationWindowAssessmentError: Error, Equatable, Sendable {
    case invalidMinimumObservedDurationNanoseconds
}

/// Evidence-derived disposition for one immutable capture session's observation
/// interval.
///
/// A successful disposition means only that Nembra retained exactly one finite
/// acquisition-ready boundary followed by a terminal observation-horizon
/// boundary with enough monotonic Nembra-observed time between them. It does not
/// prove continuous BLE traffic, RF activity, scooter uptime, target liveness,
/// protocol semantics, telemetry freshness, or physical hardware identity.
public enum PassiveBluetoothObservationWindowDisposition: String, Equatable, Sendable {
    case meetsMinimumObservedDuration
    case missingFiniteAcquisitionReadyBoundary
    case ambiguousFiniteAcquisitionReadyBoundary
    case missingObservationHorizonBoundary
    case invalidBoundaryChronology
    case observedDurationTooShort
}

/// Auditable summary of the exact immutable boundaries used to assess one
/// observation window.
///
/// Boundary watermarks are preserved as evidence-prefix identities. They are not
/// interpreted as callback counts because capture sequence numbers need only be
/// strictly increasing; they are not required to be contiguous.
public struct PassiveBluetoothObservationWindowReport: Equatable, Sendable {
    public let disposition: PassiveBluetoothObservationWindowDisposition
    public let minimumObservedDurationNanoseconds: UInt64
    public let observedDurationNanoseconds: UInt64?
    public let finiteAcquisitionReadyBoundaryCount: Int
    public let observationHorizonBoundaryCount: Int
    public let finiteAcquisitionReadyBoundary: PassiveBluetoothObservationBoundary?
    public let observationHorizonBoundary: PassiveBluetoothObservationBoundary?

    /// Reports whether the immutable raw-record watermark advanced between the
    /// two accepted boundaries. `false` is legitimate for a quiet interval and
    /// does not mean the scooter or radio was inactive; `true` only means later
    /// raw capture callbacks were accepted before the horizon.
    public var rawEvidenceAdvancedDuringWindow: Bool? {
        guard let finiteAcquisitionReadyBoundary,
              let observationHorizonBoundary else {
            return nil
        }
        return observationHorizonBoundary.recordSequenceWatermark
            > finiteAcquisitionReadyBoundary.recordSequenceWatermark
    }

    public var meetsMinimumObservedDuration: Bool {
        disposition == .meetsMinimumObservedDuration
    }

    /// Construction stays inside this source file so callers cannot mint an
    /// evidence-derived success disposition independently of the session.
    fileprivate init(
        disposition: PassiveBluetoothObservationWindowDisposition,
        minimumObservedDurationNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64?,
        finiteAcquisitionReadyBoundaryCount: Int,
        observationHorizonBoundaryCount: Int,
        finiteAcquisitionReadyBoundary: PassiveBluetoothObservationBoundary?,
        observationHorizonBoundary: PassiveBluetoothObservationBoundary?
    ) {
        self.disposition = disposition
        self.minimumObservedDurationNanoseconds = minimumObservedDurationNanoseconds
        self.observedDurationNanoseconds = observedDurationNanoseconds
        self.finiteAcquisitionReadyBoundaryCount = finiteAcquisitionReadyBoundaryCount
        self.observationHorizonBoundaryCount = observationHorizonBoundaryCount
        self.finiteAcquisitionReadyBoundary = finiteAcquisitionReadyBoundary
        self.observationHorizonBoundary = observationHorizonBoundary
    }
}

/// Assesses whether an immutable passive-capture session contains the exact
/// Nembra observation-boundary evidence required by a caller-supplied minimum
/// observation duration.
///
/// Duration is derived only from the system-boot-relative monotonic uptime clock
/// retained by the boundaries. Wall-clock dates are intentionally ignored so a
/// clock adjustment cannot manufacture or erase observed duration.
public enum PassiveBluetoothObservationWindowAssessment {
    public static func assess(
        _ session: PassiveBluetoothCaptureSession,
        minimumObservedDurationNanoseconds: UInt64
    ) throws -> PassiveBluetoothObservationWindowReport {
        guard minimumObservedDurationNanoseconds > 0 else {
            throw PassiveBluetoothObservationWindowAssessmentError
                .invalidMinimumObservedDurationNanoseconds
        }

        let readyBoundaries = session.observationBoundaries.filter {
            $0.kind == .finiteAcquisitionReady
        }
        let horizonBoundaries = session.observationBoundaries.filter {
            $0.kind == .observationHorizon
        }

        guard !readyBoundaries.isEmpty else {
            return makeReport(
                disposition: .missingFiniteAcquisitionReadyBoundary,
                minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundaries: readyBoundaries,
                horizonBoundaries: horizonBoundaries
            )
        }

        // Multiple readiness transitions inside one immutable experiment are
        // ambiguous for this assessment. Choosing first or last would silently
        // invent which interval the operator intended to qualify.
        guard readyBoundaries.count == 1 else {
            return makeReport(
                disposition: .ambiguousFiniteAcquisitionReadyBoundary,
                minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundaries: readyBoundaries,
                horizonBoundaries: horizonBoundaries
            )
        }

        guard let horizonBoundary = horizonBoundaries.first else {
            return makeReport(
                disposition: .missingObservationHorizonBoundary,
                minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundaries: readyBoundaries,
                horizonBoundaries: horizonBoundaries
            )
        }

        let readyBoundary = readyBoundaries[0]
        // PassiveBluetoothCaptureSession validates nondecreasing boundary uptime
        // and a terminal horizon before exposing this value. Keep subtraction
        // checked anyway so this layer stays fail-closed if that contract ever
        // changes rather than trapping or wrapping.
        let (observedDurationNanoseconds, underflow) =
            horizonBoundary.observedAtUptimeNanoseconds.subtractingReportingOverflow(
                readyBoundary.observedAtUptimeNanoseconds
            )
        guard !underflow else {
            return makeReport(
                disposition: .invalidBoundaryChronology,
                minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
                observedDurationNanoseconds: nil,
                readyBoundaries: readyBoundaries,
                horizonBoundaries: horizonBoundaries
            )
        }

        let disposition: PassiveBluetoothObservationWindowDisposition =
            observedDurationNanoseconds >= minimumObservedDurationNanoseconds
                ? .meetsMinimumObservedDuration
                : .observedDurationTooShort

        return makeReport(
            disposition: disposition,
            minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds,
            readyBoundaries: readyBoundaries,
            horizonBoundaries: horizonBoundaries
        )
    }

    private static func makeReport(
        disposition: PassiveBluetoothObservationWindowDisposition,
        minimumObservedDurationNanoseconds: UInt64,
        observedDurationNanoseconds: UInt64?,
        readyBoundaries: [PassiveBluetoothObservationBoundary],
        horizonBoundaries: [PassiveBluetoothObservationBoundary]
    ) -> PassiveBluetoothObservationWindowReport {
        PassiveBluetoothObservationWindowReport(
            disposition: disposition,
            minimumObservedDurationNanoseconds: minimumObservedDurationNanoseconds,
            observedDurationNanoseconds: observedDurationNanoseconds,
            finiteAcquisitionReadyBoundaryCount: readyBoundaries.count,
            observationHorizonBoundaryCount: horizonBoundaries.count,
            finiteAcquisitionReadyBoundary: readyBoundaries.count == 1 ? readyBoundaries[0] : nil,
            observationHorizonBoundary: horizonBoundaries.first
        )
    }
}
