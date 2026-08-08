import Foundation
import NembraCore

/// Software-lifecycle failures for one package-owned Experiment One attempt.
///
/// These states describe Nembra's local evidence workflow only. They do not authenticate a
/// physical scooter or imply any BLE/Tuya field semantics.
enum PassiveBluetoothExperimentOneRunError: Error, Equatable, Sendable {
    case powerCycleIncomplete
    case powerCycleAuthorityInvalid
    case powerCycleCorrelationNotUnique
    case captureRecorderAlreadyCreated
    case captureRecorderNotCreated
}

/// A completed four-window result that can be joined to Experiment One capture evidence only by
/// the package-owned run that issued both producers.
///
/// `observationSeriesIdentity` is not a second experiment token: it is the exact opaque,
/// package-issued authority already retained by all four accepted power-cycle snapshots. This type
/// is intentionally package-internal until the accepted foreground controller owns subsequent
/// recorder mutation and H-bounded finalization.
struct PassiveBluetoothExperimentOnePowerCycleEvidence: Equatable, Sendable {
    let result: PassiveBluetoothPowerCycleObservationResult
    let observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity

    init?(
        result: PassiveBluetoothPowerCycleObservationResult
    ) {
        let identities = result.correlation.observationSeriesIdentities
        guard identities.count == PassiveBluetoothPowerCycleObservationPhase.allCases.count,
              let identity = identities.first,
              identities.allSatisfy({ $0 == identity }) else {
            return nil
        }

        self.result = result
        observationSeriesIdentity = identity
    }
}

/// An immutable capture snapshot bound to the exact package-issued power-cycle producer authority
/// that opened the capture phase.
///
/// This is package-internal: public raw `PassiveBluetoothCaptureSession` remains useful research
/// evidence, but app/UI code cannot promote an arbitrary capture into this authority-bearing input.
struct PassiveBluetoothExperimentOneCaptureEvidence: Equatable, Sendable {
    let session: PassiveBluetoothCaptureSession
    let observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity

    init(
        observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity,
        session: PassiveBluetoothCaptureSession
    ) {
        self.observationSeriesIdentity = observationSeriesIdentity
        self.session = session
    }
}

/// Package-internal provenance root for one complete Experiment One attempt.
///
/// One instance owns one four-window producer. Only after that exact producer finishes under one
/// valid package-issued `PassiveBluetoothCandidateObservationSeriesIdentity` with one unique
/// repeated full UUID may the run create its capture recorder. Subsequent capture evidence retains
/// that same producer identity. A different producer life receives a different package-issued
/// identity even when CoreBluetooth later reports the same peripheral UUID, so stale/swapped
/// same-UUID artifacts cannot satisfy Experiment One composition.
///
/// Experiment One's 10-second per-window policy is fixed inside this product-specific owner. The
/// caller cannot shorten it to reach capture acquisition sooner. That duration remains a local
/// callback-receipt procedure threshold, not a BLE cadence or RF-completeness claim.
///
/// **Critical integration boundary:** this run and all authority-bearing result types remain
/// package-internal until the accepted foreground CoreBluetooth controller can create/use the
/// recorder internally and emit a finalized H-bounded artifact under current controller authority.
/// The general-purpose public recorder is deliberately *not* exposed through this run. Therefore
/// ordinary app/UI code cannot obtain the authority-bearing mutable recorder, inject fabricated
/// GATT evidence, or call an Experiment One PASS evaluator. Physical Experiment One remains blocked.
@MainActor
final class PassiveBluetoothExperimentOneRun {
    let vehicleIdentity: VehicleIdentity
    let powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession

    private var captureRecorder: PassiveCoreBluetoothCaptureRecorder?
    private var captureObservationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity?

    init(vehicleIdentity: VehicleIdentity) throws {
        self.vehicleIdentity = vehicleIdentity
        powerCycleObservationSession = try PassiveBluetoothPowerCycleObservationSession(
            minimumWindowDuration: TimeInterval(
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
            ) / 1_000_000_000
        )
    }

    /// Bound evidence exists only after this run's exact package-owned four-window producer has
    /// completed under one valid observation-series authority.
    var completedPowerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence? {
        guard let result = powerCycleObservationSession.result else { return nil }
        return PassiveBluetoothExperimentOnePowerCycleEvidence(result: result)
    }

    var hasCaptureRecorder: Bool {
        captureRecorder != nil
    }

    /// Package-internal only. The future live coordinator may use this exact recorder as the one
    /// injected into/owned by the corrected foreground controller. Starting capture retains the
    /// exact existing power-cycle producer authority; no caller-supplied identity is accepted.
    @discardableResult
    func beginCaptureRecorder(
        startedAt: Date = Date()
    ) throws -> PassiveCoreBluetoothCaptureRecorder {
        guard captureRecorder == nil else {
            throw PassiveBluetoothExperimentOneRunError.captureRecorderAlreadyCreated
        }
        guard powerCycleObservationSession.result != nil else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleIncomplete
        }
        guard let evidence = completedPowerCycleEvidence else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleAuthorityInvalid
        }
        guard case .singleRepeatableCandidate(_) = evidence.result.correlation.disposition else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleCorrelationNotUnique
        }

        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        captureObservationSeriesIdentity = evidence.observationSeriesIdentity
        captureRecorder = recorder
        return recorder
    }

    /// Snapshots only this run's exact internally held recorder and binds that immutable session to
    /// the producer authority captured atomically when the run entered its capture phase.
    func captureEvidenceSnapshot() async throws -> PassiveBluetoothExperimentOneCaptureEvidence {
        guard let captureRecorder else {
            throw PassiveBluetoothExperimentOneRunError.captureRecorderNotCreated
        }
        guard let captureObservationSeriesIdentity else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleAuthorityInvalid
        }
        return PassiveBluetoothExperimentOneCaptureEvidence(
            observationSeriesIdentity: captureObservationSeriesIdentity,
            session: await captureRecorder.snapshot()
        )
    }

    /// Internal one-shot structural boundary for tests/future live integration. This cannot be an
    /// app-facing completion signal until the controller owns recorder mutation and finalized
    /// H-bounded artifact production under accepted controller authority.
    func captureEvidenceAssessment() async throws -> PassiveBluetoothExperimentOneCaptureEvidenceAssessment {
        guard powerCycleObservationSession.result != nil else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleIncomplete
        }
        guard let powerCycleEvidence = completedPowerCycleEvidence else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleAuthorityInvalid
        }
        let captureEvidence = try await captureEvidenceSnapshot()
        return PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleEvidence: powerCycleEvidence,
            captureEvidence: captureEvidence
        )
    }
}
