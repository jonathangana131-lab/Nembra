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

/// Package-internal fail-closed composition of the software evidence required from Experiment One.
///
/// This type deliberately is not public yet. Until the accepted foreground controller owns the
/// authority-bearing recorder and H-bounded finalization, ordinary app/UI code must have **no API**
/// that can turn public raw capture/session constructors into an Experiment One coherent PASS.
/// Public raw evidence remains available for research and offline analysis only.
///
/// Once invoked by the package-owned producer path, composition closes these evidence boundaries:
/// - both opaque inputs must retain the same exact package-issued power-cycle observation-series
///   identity before UUID/duration can contribute at all;
/// - the exact four receipt-bounded OFF₁ -> ON₁ -> OFF₂ -> ON₂ result must meet Experiment One's
///   per-window duration policy;
/// - the raw package-issued candidate snapshots must still align with their window receipts and
///   replay to the exact stored correlation report;
/// - correlation must contain exactly one repeated full CoreBluetooth UUID;
/// - the immutable capture must resolve to exactly one typed GATT-path peripheral, and that UUID
///   must equal the repeated correlation candidate;
/// - the exact capture session must contain a sufficient, uninterrupted monotonic
///   finite-acquisition-ready -> observation-horizon interval.
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
        /// Raw candidate catalogs, receipt sequences, or the stored derived report disagree.
        case powerCycleEvidenceInconsistent
        case correlationRejected(PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition)
        /// Zero or multiple typed GATT-path peripheral identifiers were present in the capture.
        case captureTargetUnresolved
        case captureTargetIdentifierMalformed(String)
        case captureTargetMismatch(correlated: UUID, captured: UUID)
        case observationDurationRejected(PassiveBluetoothObservationWindowDurationAssessment.Status)
        case coherentCaptureEvidence(UUID)
    }

    let status: Status
    let powerCycleDurationAssessment: PassiveBluetoothPowerCycleObservationWindowDurationAssessment
    let observationDurationAssessment: PassiveBluetoothObservationWindowDurationAssessment

    /// Exact source capture identity/context assessed for the post-ready observation interval.
    let captureSessionID: UUID
    let vehicleIdentity: VehicleIdentity

    /// Sorted exact identifier strings seen on typed GATT-path evidence. Advertisement-only and
    /// connection-only neighbors are deliberately excluded from target attribution.
    let captureGATTPeripheralIdentifiers: [String]

    /// Present only when the replayed correlation report has exactly one repeated full UUID.
    let correlatedPeripheralIdentifier: UUID?
    /// Present only when the capture has one syntactically valid UUID on typed GATT-path evidence.
    let capturedPeripheralIdentifier: UUID?

    var isCaptureEvidenceCoherent: Bool {
        if case .coherentCaptureEvidence(_) = status { return true }
        return false
    }

    private init(
        status: Status,
        powerCycleDurationAssessment: PassiveBluetoothPowerCycleObservationWindowDurationAssessment,
        observationDurationAssessment: PassiveBluetoothObservationWindowDurationAssessment,
        captureSessionID: UUID,
        vehicleIdentity: VehicleIdentity,
        captureGATTPeripheralIdentifiers: [String],
        correlatedPeripheralIdentifier: UUID?,
        capturedPeripheralIdentifier: UUID?
    ) {
        self.status = status
        self.powerCycleDurationAssessment = powerCycleDurationAssessment
        self.observationDurationAssessment = observationDurationAssessment
        self.captureSessionID = captureSessionID
        self.vehicleIdentity = vehicleIdentity
        self.captureGATTPeripheralIdentifiers = captureGATTPeripheralIdentifiers
        self.correlatedPeripheralIdentifier = correlatedPeripheralIdentifier
        self.capturedPeripheralIdentifier = capturedPeripheralIdentifier
    }

    /// Recomputes every component from package-bound evidence instead of accepting raw independently
    /// produced artifacts, detached caller-authored booleans, or weakened thresholds.
    static func assess(
        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
        captureEvidence: PassiveBluetoothExperimentOneCaptureEvidence
    ) -> Self {
        let powerCycleResult = powerCycleEvidence.result
        let captureSession = captureEvidence.session

        let powerCycleDuration = PassiveBluetoothPowerCycleObservationWindowDurationAssessment.assess(
            result: powerCycleResult,
            minimumDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
        )
        let observationDuration = PassiveBluetoothObservationWindowDurationAssessment.assess(
            session: captureSession,
            minimumDurationNanoseconds:
                PassiveBluetoothExperimentOneCapturePolicy.minimumPostReadyObservationDurationNanoseconds
        )
        let captureIdentifiers = gattPeripheralIdentifiers(in: captureSession)

        let replayedCorrelation = replayedCorrelationIfConsistent(with: powerCycleResult)
        let correlatedIdentifier: UUID?
        if let replayedCorrelation,
           case let .singleRepeatableCandidate(identifier) = replayedCorrelation.disposition {
            correlatedIdentifier = identifier
        } else {
            correlatedIdentifier = nil
        }

        let capturedIdentifier: UUID?
        if captureIdentifiers.count == 1 {
            capturedIdentifier = UUID(uuidString: captureIdentifiers[0])
        } else {
            capturedIdentifier = nil
        }

        let status: Status
        if powerCycleEvidence.observationSeriesIdentity != captureEvidence.observationSeriesIdentity {
            status = .observationSeriesAuthorityMismatch
        } else if !powerCycleDuration.isDurationSufficient {
            status = .powerCycleDurationRejected(powerCycleDuration.status)
        } else if replayedCorrelation == nil || replayedCorrelation != powerCycleResult.correlation {
            status = .powerCycleEvidenceInconsistent
        } else if let replayedCorrelation,
                  case .singleRepeatableCandidate(_) = replayedCorrelation.disposition {
            if captureIdentifiers.count != 1 {
                status = .captureTargetUnresolved
            } else if capturedIdentifier == nil {
                status = .captureTargetIdentifierMalformed(captureIdentifiers[0])
            } else if let correlatedIdentifier,
                      let capturedIdentifier,
                      correlatedIdentifier != capturedIdentifier {
                status = .captureTargetMismatch(
                    correlated: correlatedIdentifier,
                    captured: capturedIdentifier
                )
            } else if !observationDuration.isDurationSufficient {
                status = .observationDurationRejected(observationDuration.status)
            } else if let correlatedIdentifier {
                status = .coherentCaptureEvidence(correlatedIdentifier)
            } else {
                // Defensive fail-closed fallback: the pattern above should have produced an ID.
                status = .powerCycleEvidenceInconsistent
            }
        } else if let replayedCorrelation {
            status = .correlationRejected(replayedCorrelation.disposition)
        } else {
            status = .powerCycleEvidenceInconsistent
        }

        return Self(
            status: status,
            powerCycleDurationAssessment: powerCycleDuration,
            observationDurationAssessment: observationDuration,
            captureSessionID: captureSession.id,
            vehicleIdentity: captureSession.vehicleIdentity,
            captureGATTPeripheralIdentifiers: captureIdentifiers,
            correlatedPeripheralIdentifier: correlatedIdentifier,
            capturedPeripheralIdentifier: capturedIdentifier
        )
    }

    /// Replays correlation only when the preserved raw catalogs still line up one-for-one with the
    /// receipt sequences that describe the four canonical windows.
    private static func replayedCorrelationIfConsistent(
        with result: PassiveBluetoothPowerCycleObservationResult
    ) -> PassiveBluetoothPowerCycleTargetCorrelationReport? {
        let expectedCount = PassiveBluetoothPowerCycleObservationPhase.allCases.count
        guard result.windows.count == expectedCount,
              result.observationSnapshots.count == expectedCount,
              zip(result.windows, result.observationSnapshots).allSatisfy({ pair in
                  pair.0.windowSequence == pair.1.windowSequence
              }) else {
            return nil
        }

        return PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
    }

    /// Mirrors Nembra's conservative comparison target rule: only typed GATT-path evidence can
    /// establish a capture target. Advertisement and connection observations are intentionally not
    /// enough because nearby devices may coexist in the same capture environment.
    private static func gattPeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession
    ) -> [String] {
        var identifiers = Set<String>()

        for record in session.records {
            switch record.event {
            case let .service(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .includedService(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .characteristic(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .descriptor(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .subscription(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case let .value(observation):
                identifiers.insert(observation.peripheralIdentifier)
            case .advertisement, .connection, .stockAppState, .interruption:
                continue
            }
        }

        return identifiers.sorted()
    }
}
