import Foundation
import NembraCore

/// Fixed evidence thresholds for Nembra's first stationary ES80 fingerprint procedure.
///
/// These values are procedure policy only. Ten seconds per OFF/ON candidate window is not a BLE
/// cadence claim, and sixty seconds after finite acquisition readiness is not proof of continuous
/// RF traffic. Changing this policy requires an explicit experiment revision rather than a caller
/// silently weakening a minimum at the product boundary.
public enum PassiveBluetoothExperimentOneCapturePolicy {
    public static let minimumPowerCycleWindowDurationNanoseconds: UInt64 = 10_000_000_000
    public static let minimumPostReadyObservationDurationNanoseconds: UInt64 = 60_000_000_000
}

/// Package-internal authority-bearing composition for Experiment One software evidence.
///
/// Raw replay/target/duration policy is delegated to
/// `PassiveBluetoothExperimentOneStructuralEvidenceAssessment`, whose output is deliberately
/// descriptive-only and directly testable. That evaluator cannot issue Experiment One authority.
/// This type accepts only producer-private evidence wrappers and first requires exact continuity of
/// the package-issued power-cycle observation-series identity before a structurally coherent result
/// can become authority-bearing coherence.
///
/// This type deliberately is not public yet. Until the accepted foreground controller owns the
/// authority-bearing recorder and H-bounded finalization, ordinary app/UI code must have **no API**
/// that can turn public raw capture/session constructors into an Experiment One coherent PASS.
///
/// A coherent result is **software capture evidence**, not physical ES80 authentication. It does not
/// prove that the operator actually changed scooter power state, that OFF-window non-observation is
/// physical absence, that radio traffic was complete, that a CoreBluetooth UUID is permanent, or
/// that any GATT/Tuya field has vehicle semantics. Raw-byte provenance and offline protocol analysis
/// remain separate gates.
struct PassiveBluetoothExperimentOneCaptureEvidenceAssessment: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// The two otherwise-valid artifacts were issued under different package-owned power-cycle
        /// producer lives. UUID equality cannot repair this provenance break.
        case observationSeriesAuthorityMismatch
        case powerCycleDurationRejected(
            PassiveBluetoothPowerCycleObservationWindowDurationAssessment.Status
        )
        case powerCycleEvidenceInconsistent
        case correlationRejected(PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition)
        case captureTargetUnresolved
        case captureTargetIdentifierMalformed(String)
        case captureTargetMismatch(correlated: UUID, captured: UUID)
        case observationDurationRejected(PassiveBluetoothObservationWindowDurationAssessment.Status)
        case coherentCaptureEvidence(UUID)
    }

    let status: Status
    let powerCycleDurationAssessment: PassiveBluetoothPowerCycleObservationWindowDurationAssessment
    let observationDurationAssessment: PassiveBluetoothObservationWindowDurationAssessment
    let captureSessionID: UUID
    let vehicleIdentity: VehicleIdentity
    let captureGATTPeripheralIdentifiers: [String]
    let correlatedPeripheralIdentifier: UUID?
    let capturedPeripheralIdentifier: UUID?

    var isCaptureEvidenceCoherent: Bool {
        if case .coherentCaptureEvidence(_) = status { return true }
        return false
    }

    private init(
        status: Status,
        structural: PassiveBluetoothExperimentOneStructuralEvidenceAssessment
    ) {
        self.status = status
        powerCycleDurationAssessment = structural.powerCycleDurationAssessment
        observationDurationAssessment = structural.observationDurationAssessment
        captureSessionID = structural.captureSessionID
        vehicleIdentity = structural.vehicleIdentity
        captureGATTPeripheralIdentifiers = structural.captureGATTPeripheralIdentifiers
        correlatedPeripheralIdentifier = structural.correlatedPeripheralIdentifier
        capturedPeripheralIdentifier = structural.capturedPeripheralIdentifier
    }

    /// Converts descriptive structural analysis into authority-bearing software coherence only for
    /// producer-private wrappers that retain the exact same package-issued observation-series life.
    static func assess(
        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
        captureEvidence: PassiveBluetoothExperimentOneCaptureEvidence
    ) -> Self {
        let structural = PassiveBluetoothExperimentOneStructuralEvidenceAssessment.assess(
            powerCycleResult: powerCycleEvidence.result,
            captureSession: captureEvidence.session
        )

        guard PassiveBluetoothExperimentOneStructuralEvidenceAssessment
            .observationSeriesAuthorityMatches(
                powerCycle: powerCycleEvidence.observationSeriesIdentity,
                capture: captureEvidence.observationSeriesIdentity
            ) else {
            return Self(status: .observationSeriesAuthorityMismatch, structural: structural)
        }

        let status: Status
        switch structural.status {
        case let .powerCycleDurationRejected(reason):
            status = .powerCycleDurationRejected(reason)
        case .powerCycleEvidenceInconsistent:
            status = .powerCycleEvidenceInconsistent
        case let .correlationRejected(disposition):
            status = .correlationRejected(disposition)
        case .captureTargetUnresolved:
            status = .captureTargetUnresolved
        case let .captureTargetIdentifierMalformed(identifier):
            status = .captureTargetIdentifierMalformed(identifier)
        case let .captureTargetMismatch(correlated, captured):
            status = .captureTargetMismatch(correlated: correlated, captured: captured)
        case let .observationDurationRejected(reason):
            status = .observationDurationRejected(reason)
        case let .structurallyCoherent(identifier):
            status = .coherentCaptureEvidence(identifier)
        }

        return Self(status: status, structural: structural)
    }
}
