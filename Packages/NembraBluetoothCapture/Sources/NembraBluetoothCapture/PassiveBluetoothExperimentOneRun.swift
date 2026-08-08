import Foundation
import NembraCore

/// Software-lifecycle failures for one package-owned Experiment One attempt.
///
/// These states describe Nembra's local evidence workflow only. They do not authenticate a
/// physical scooter or imply any BLE/Tuya field semantics.
public enum PassiveBluetoothExperimentOneRunError: Error, Equatable, Sendable {
    case powerCycleIncomplete
    case powerCycleCorrelationNotUnique
    case captureRecorderAlreadyCreated
    case captureRecorderNotCreated
}

/// A completed four-window result that can be joined to Experiment One capture evidence only by
/// the package-owned run that issued both producers.
///
/// The run authority is deliberately not public and there is no public initializer. External
/// callers therefore cannot take an arbitrary older power-cycle result and stamp it as belonging
/// to a newer capture run.
public struct PassiveBluetoothExperimentOnePowerCycleEvidence: Equatable, Sendable {
    public let result: PassiveBluetoothPowerCycleObservationResult
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
/// There is intentionally no public initializer. Imported/raw capture sessions remain useful
/// research artifacts, but cannot be promoted into Experiment One closure evidence by a caller
/// merely matching a CoreBluetooth UUID.
public struct PassiveBluetoothExperimentOneCaptureEvidence: Equatable, Sendable {
    public let session: PassiveBluetoothCaptureSession
    let runAuthorityID: UUID

    init(
        runAuthorityID: UUID,
        session: PassiveBluetoothCaptureSession
    ) {
        self.runAuthorityID = runAuthorityID
        self.session = session
    }
}

/// Owns the software provenance root for one complete Experiment One attempt.
///
/// One instance issues exactly one four-window producer and, only after that producer finishes with
/// one unique repeated full UUID, at most one passive capture recorder. Evidence snapshots emitted
/// by this object carry the same package-generated run authority. A different `ExperimentOneRun`
/// receives a different authority even when CoreBluetooth later reports the same peripheral UUID,
/// so stale/swapped same-UUID artifacts cannot satisfy the public evidence-composition API.
///
/// Experiment One's 10-second per-window policy is fixed inside this product-specific owner. The
/// caller cannot shorten it to reach capture acquisition sooner. That duration remains a local
/// callback-receipt procedure threshold, not a BLE cadence or RF-completeness claim.
///
/// This type intentionally does **not** connect the existing foreground GATT controller to the
/// recorder yet. Until that integration is made explicitly, the real physical experiment remains
/// blocked rather than silently wrapping an independently owned capture as same-run evidence.
@MainActor
public final class PassiveBluetoothExperimentOneRun {
    public let vehicleIdentity: VehicleIdentity
    public let powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession

    private let runAuthorityID = UUID()
    private var captureRecorder: PassiveCoreBluetoothCaptureRecorder?

    public init(vehicleIdentity: VehicleIdentity) throws {
        self.vehicleIdentity = vehicleIdentity
        powerCycleObservationSession = try PassiveBluetoothPowerCycleObservationSession(
            minimumWindowDuration: TimeInterval(
                PassiveBluetoothExperimentOneCapturePolicy.minimumPowerCycleWindowDurationNanoseconds
            ) / 1_000_000_000
        )
    }

    /// Bound evidence exists only after this run's exact package-owned four-window producer has
    /// completed. Callers cannot substitute a detached result into this property.
    public var completedPowerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence? {
        guard let result = powerCycleObservationSession.result else { return nil }
        return PassiveBluetoothExperimentOnePowerCycleEvidence(
            runAuthorityID: runAuthorityID,
            result: result
        )
    }

    public var hasCaptureRecorder: Bool {
        captureRecorder != nil
    }

    /// Creates the only passive recorder whose snapshots this run can later promote into bound
    /// Experiment One capture evidence.
    ///
    /// The recorder cannot be created before the four-window producer finishes with exactly one
    /// repeated full UUID. This is still software correlation evidence, never scooter identity.
    @discardableResult
    public func beginCaptureRecorder(
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

    /// Snapshots only this run's exact recorder and binds that immutable session to the same hidden
    /// authority as the completed four-window result. There is no API that accepts an arbitrary
    /// `PassiveBluetoothCaptureSession` here.
    public func captureEvidenceSnapshot() async throws -> PassiveBluetoothExperimentOneCaptureEvidence {
        guard let captureRecorder else {
            throw PassiveBluetoothExperimentOneRunError.captureRecorderNotCreated
        }
        return PassiveBluetoothExperimentOneCaptureEvidence(
            runAuthorityID: runAuthorityID,
            session: await captureRecorder.snapshot()
        )
    }

    /// One-shot product boundary for the exact sources owned by this run. This method cannot join a
    /// four-window result from run A to capture recorder B because neither raw artifact is accepted
    /// as an argument.
    public func captureEvidenceAssessment() async throws -> PassiveBluetoothExperimentOneCaptureEvidenceAssessment {
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
