import Foundation
import NembraCore

/// Deterministic, descriptive-only structural analysis for raw Experiment One research artifacts.
///
/// This evaluator intentionally accepts raw values so the fail-closed decision matrix can be tested
/// without reopening the producer-private authority wrappers. Its output is **not** Experiment One
/// authority and cannot be promoted to a product PASS. Only the sealed authority-bearing assessor
/// may combine producer-issued evidence after checking exact observation-series continuity.
///
/// A `.structurallyCoherent` result means only that the supplied software artifacts satisfy these
/// local consistency rules. It does not authenticate an AOVOPRO ES80, prove physical OFF/ON state,
/// prove RF completeness, make a CoreBluetooth UUID permanent, or assign GATT/Tuya/DP semantics.
struct PassiveBluetoothExperimentOneStructuralEvidenceAssessment: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case powerCycleDurationRejected(
            PassiveBluetoothPowerCycleObservationWindowDurationAssessment.Status
        )
        case powerCycleEvidenceInconsistent
        case correlationRejected(PassiveBluetoothPowerCycleTargetCorrelationReport.Disposition)
        case captureTargetUnresolved
        case captureTargetIdentifierMalformed(String)
        case captureTargetMismatch(correlated: UUID, captured: UUID)
        case observationDurationRejected(PassiveBluetoothObservationWindowDurationAssessment.Status)
        case structurallyCoherent(UUID)
    }

    let status: Status
    let powerCycleDurationAssessment: PassiveBluetoothPowerCycleObservationWindowDurationAssessment
    let observationDurationAssessment: PassiveBluetoothObservationWindowDurationAssessment
    let captureSessionID: UUID
    let vehicleIdentity: VehicleIdentity
    let captureGATTPeripheralIdentifiers: [String]
    let correlatedPeripheralIdentifier: UUID?
    let capturedPeripheralIdentifier: UUID?

    var isStructurallyCoherent: Bool {
        if case .structurallyCoherent(_) = status { return true }
        return false
    }

    static func assess(
        powerCycleResult: PassiveBluetoothPowerCycleObservationResult,
        captureSession: PassiveBluetoothCaptureSession
    ) -> Self {
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
        let replayedCorrelation = replayedCorrelationIfConsistent(with: powerCycleResult)

        let correlatedIdentifier: UUID?
        if let replayedCorrelation,
           case let .singleRepeatableCandidate(identifier) = replayedCorrelation.disposition {
            correlatedIdentifier = identifier
        } else {
            correlatedIdentifier = nil
        }

        // Target attribution is only meaningful through one accepted Horizon watermark. Records
        // appended after H are never allowed to establish, replace, or make ambiguous the target for
        // this structural experiment decision. If duration/Horizon evidence itself is invalid, target
        // evidence remains deliberately empty and the observation-duration status wins below.
        let captureIdentifiers: [String]
        if observationDuration.isDurationSufficient,
           let horizon = observationDuration.horizonBoundary {
            captureIdentifiers = gattPeripheralIdentifiers(
                in: captureSession,
                throughSequenceNumber: horizon.recordSequenceWatermark
            )
        } else {
            captureIdentifiers = []
        }

        let capturedIdentifier: UUID?
        if captureIdentifiers.count == 1 {
            capturedIdentifier = UUID(uuidString: captureIdentifiers[0])
        } else {
            capturedIdentifier = nil
        }

        let status: Status
        if !powerCycleDuration.isDurationSufficient {
            status = .powerCycleDurationRejected(powerCycleDuration.status)
        } else if replayedCorrelation == nil || replayedCorrelation != powerCycleResult.correlation {
            status = .powerCycleEvidenceInconsistent
        } else if let replayedCorrelation,
                  case .singleRepeatableCandidate(_) = replayedCorrelation.disposition {
            if !observationDuration.isDurationSufficient {
                status = .observationDurationRejected(observationDuration.status)
            } else if captureIdentifiers.count != 1 {
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
            } else if let correlatedIdentifier {
                status = .structurallyCoherent(correlatedIdentifier)
            } else {
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

    /// Descriptive equality check used by the authority-bearing assessor before any structural
    /// result can become coherent authority. Exposing this pure predicate to the test target does
    /// not issue or construct authority-bearing evidence.
    static func observationSeriesAuthorityMatches(
        powerCycle: PassiveBluetoothCandidateObservationSeriesIdentity,
        capture: PassiveBluetoothCandidateObservationSeriesIdentity
    ) -> Bool {
        powerCycle == capture
    }

    /// Replays correlation only when the preserved raw snapshots still match the canonical receipt
    /// metadata and serial monotonic chronology that claim to describe them. Experiment One's live
    /// one-window-at-a-time producer issues the first series exactly as OFF1/ON1/OFF2/ON2 sequence
    /// 1/2/3/4; generic correlation intentionally accepts any strictly increasing sequence, but an
    /// imported Experiment One artifact may not substitute detached increasing counters. Phase,
    /// exact sequence, receipt candidate counts, and cross-window clock order must all agree with
    /// what that producer can issue.
    private static func replayedCorrelationIfConsistent(
        with result: PassiveBluetoothPowerCycleObservationResult
    ) -> PassiveBluetoothPowerCycleTargetCorrelationReport? {
        let expectedPhases = PassiveBluetoothPowerCycleObservationPhase.allCases
        guard result.windows.count == expectedPhases.count,
              result.observationSnapshots.count == expectedPhases.count else {
            return nil
        }

        var previousEndedAtUptimeNanoseconds: UInt64?
        for index in expectedPhases.indices {
            let receipt = result.windows[index]
            let snapshot = result.observationSnapshots[index]

            if let previousEndedAtUptimeNanoseconds,
               receipt.startedAtUptimeNanoseconds < previousEndedAtUptimeNanoseconds {
                return nil
            }

            guard receipt.phase == expectedPhases[index],
                  receipt.windowSequence.rawValue == UInt64(index + 1),
                  receipt.windowSequence == snapshot.windowSequence,
                  receipt.observedCandidateCount == snapshot.candidates.count else {
                return nil
            }
            previousEndedAtUptimeNanoseconds = receipt.endedAtUptimeNanoseconds
        }

        return PassiveBluetoothPowerCycleTargetCorrelation.assess(
            firstOff: result.observationSnapshots[0],
            firstOn: result.observationSnapshots[1],
            secondOff: result.observationSnapshots[2],
            secondOn: result.observationSnapshots[3]
        )
    }

    private static func gattPeripheralIdentifiers(
        in session: PassiveBluetoothCaptureSession,
        throughSequenceNumber horizonWatermark: UInt64
    ) -> [String] {
        var identifiers = Set<String>()

        for record in session.records where record.sequenceNumber <= horizonWatermark {
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