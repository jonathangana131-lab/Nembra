import Foundation
import NembraCore

/// Software-lifecycle failures for one package-owned Experiment One attempt.
///
/// These states describe Nembra's local evidence workflow only. They do not authenticate a
/// physical scooter or imply any BLE/Tuya field semantics.
enum PassiveBluetoothExperimentOneRunError: Error, Equatable, Sendable {
    case powerCycleIncomplete
    case powerCycleCorrelationNotUnique
    case captureRecorderAlreadyCreated
    case captureRecorderNotCreated
}

/// A completed four-window result that can be joined to Experiment One capture evidence only by
/// the package-owned run that issued both producers.
///
/// This type is intentionally package-internal until the accepted foreground controller owns the
/// subsequent recorder and H-bounded finalization. Ordinary clients cannot construct or retain an
/// authority-bearing Experiment One handoff from an arbitrary raw result.
struct PassiveBluetoothExperimentOnePowerCycleEvidence: Equatable, Sendable {
    let result: PassiveBluetoothPowerCycleObservationResult
    let runAuthorityID: UUID

    init(
        runAuthorityID: UUID,
        result: PassiveBluetoothPowerCycleObservationResult
    ) {
        self.runAuthorityID = runAuthorityID
        self.result = result
    }
}

/// An immutable capture snapshot bound to the same package-owned Experiment One run authority as
/// its power-cycle producer.
///
/// This is package-internal for the same reason as the run itself: a public raw
/// `PassiveBluetoothCaptureSession` remains useful research/offline evidence, but must not be
/// promotable by app/UI code into an authority-bearing Experiment One completion input.
struct PassiveBluetoothExperimentOneCaptureEvidence: Equatable, Sendable {
    let session: PassiveBluetoothCaptureSession
    let runAuthorityID: UUID

    init(
        runAuthorityID: UUID,
        session: PassiveBluetoothCaptureSession
    ) {
        self.runAuthorityID = runAuthorityID
        self.session = session
    }
}

/// Package-internal provenance root for one complete Experiment One attempt.
///
/// One instance issues exactly one four-window producer and, only after that producer finishes with
/// one unique repeated full UUID, at most one passive capture recorder. Evidence snapshots emitted
/// by this object carry the same package-generated run authority. A different run receives a
/// different authority even when CoreBluetooth later reports the same peripheral UUID, so
/// stale/swapped same-UUID artifacts cannot satisfy the package-owned evidence composition.
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

    private let runAuthorityID = UUID()
    private var captureRecorder: PassiveCoreBluetoothCaptureRecorder?

    init(vehicleIdentity: VehicleIdentity) throws {
        self.vehicleIdentity = vehicleIdentity
        powerCycleObservationSession = try PassiveBluetoothPowerCycleObservationSession(
            minimumWindowDuration: TimeInterval(
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
            ) / 1_000_000_000
        )
    }

    /// Bound evidence exists only after this run's exact package-owned four-window producer has
    /// completed. No external caller can substitute a detached result into this property.
    var completedPowerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence? {
        guard let result = powerCycleObservationSession.result else { return nil }
        return PassiveBluetoothExperimentOnePowerCycleEvidence(
            runAuthorityID: runAuthorityID,
            result: result
        )
    }

    var hasCaptureRecorder: Bool {
        captureRecorder != nil
    }

    /// Package-internal only. The future live coordinator may use this exact recorder as the one
    /// injected into/owned by the corrected foreground controller. It must never be surfaced as the
    /// app-facing authority-bearing capture handoff.
    @discardableResult
    func beginCaptureRecorder(
        startedAt: Date = Date()
    ) throws -> PassiveCoreBluetoothCaptureRecorder {
        guard captureRecorder == nil else {
            throw PassiveBluetoothExperimentOneRunError.captureRecorderAlreadyCreated
        }
        guard let evidence = completedPowerCycleEvidence else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleIncomplete
        }
        guard case .singleRepeatableCandidate(_) = evidence.result.correlation.disposition else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleCorrelationNotUnique
        }

        let recorder = try PassiveCoreBluetoothCaptureRecorder(
            vehicleIdentity: vehicleIdentity,
            startedAt: startedAt
        )
        captureRecorder = recorder
        return recorder
    }

    /// Snapshots only this run's exact internally held recorder and binds that immutable session to
    /// the same hidden authority as the completed four-window result.
    func captureEvidenceSnapshot() async throws -> PassiveBluetoothExperimentOneCaptureEvidence {
        guard let captureRecorder else {
            throw PassiveBluetoothExperimentOneRunError.captureRecorderNotCreated
        }
        return PassiveBluetoothExperimentOneCaptureEvidence(
            runAuthorityID: runAuthorityID,
            session: await captureRecorder.snapshot()
        )
    }

    /// Internal one-shot structural boundary for tests/future live integration. This cannot be an
    /// app-facing completion signal until the controller owns recorder mutation and finalized
    /// H-bounded artifact production under accepted controller authority.
    func captureEvidenceAssessment() async throws -> PassiveBluetoothExperimentOneCaptureEvidenceAssessment {
        guard let powerCycleEvidence = completedPowerCycleEvidence else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleIncomplete
        }
        let captureEvidence = try await captureEvidenceSnapshot()
        return PassiveBluetoothExperimentOneCaptureEvidenceAssessment.assess(
            powerCycleEvidence: powerCycleEvidence,
            captureEvidence: captureEvidence
        )
    }
}
