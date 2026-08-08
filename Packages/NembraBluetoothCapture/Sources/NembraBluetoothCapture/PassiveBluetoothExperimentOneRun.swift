import Foundation
import NembraCore

/// Software-lifecycle failures for one package-owned Experiment One attempt.
///
/// These states describe Nembra's local evidence workflow only. They do not authenticate a
/// physical scooter or imply any BLE/Tuya field semantics.
enum PassiveBluetoothExperimentOneRunError: Error, Equatable, Sendable {
    case invalidVehicleContext
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

    /// Issuance is producer-file private. Other production files in this module may inspect an
    /// issued value but cannot wrap an arbitrary detached result as Experiment One authority.
    fileprivate init?(
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

    /// Issuance is producer-file private for the same reason as power-cycle evidence: same-module
    /// consumers cannot join an arbitrary raw capture to a caller-chosen matching authority token.
    fileprivate init(
        observationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity,
        session: PassiveBluetoothCaptureSession
    ) {
        self.observationSeriesIdentity = observationSeriesIdentity
        self.session = session
    }
}

/// One package-internal, one-shot handoff from the sealed Experiment One provenance root into the
/// live Capture controller.
///
/// The app cannot construct or consume this type because it is not public. Construction is even
/// narrower: only this producer file can initialize one, and the initializer accepts the exact
/// producer-issued four-window evidence plus the recorder already owned by the same run. No UUID,
/// observation result, recorder, or authority supplied by app/UI code can manufacture admission.
///
/// `consume()` is MainActor-isolated and one-shot. Aliasing the reference does not create another
/// permit; the first consumer permanently burns the handoff. The returned payload also has a
/// producer-file-private initializer and carries a process-local admission UUID, so a future
/// controller can bind one exact consumption event instead of trusting equal scalar fields.
///
/// This is software ownership authority only. It does not authenticate the correlated physical
/// device or assign any GATT/Tuya meaning.
@MainActor
final class PassiveBluetoothExperimentOneCaptureAdmission {
    enum ConsumptionError: Error, Equatable, Sendable {
        case alreadyConsumed
    }

    struct StagingPreview: Equatable, Sendable {
        let admissionIdentity: UUID
        let peripheralIdentifier: UUID
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64

        fileprivate init(
            admissionIdentity: UUID,
            peripheralIdentifier: UUID,
            issuedAtUptimeNanoseconds: UInt64
        ) {
            self.admissionIdentity = admissionIdentity
            self.peripheralIdentifier = peripheralIdentifier
            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds
        }
    }

    struct Payload {
        let admissionIdentity: UUID
        let powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence
        let peripheralIdentifier: UUID
        let recorder: PassiveCoreBluetoothCaptureRecorder
        /// Local monotonic handoff boundary. This is callback chronology only, never RF emission time.
        let issuedAtUptimeNanoseconds: UInt64

        fileprivate init(
            admissionIdentity: UUID,
            powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
            peripheralIdentifier: UUID,
            recorder: PassiveCoreBluetoothCaptureRecorder,
            issuedAtUptimeNanoseconds: UInt64
        ) {
            self.admissionIdentity = admissionIdentity
            self.powerCycleEvidence = powerCycleEvidence
            self.peripheralIdentifier = peripheralIdentifier
            self.recorder = recorder
            self.issuedAtUptimeNanoseconds = issuedAtUptimeNanoseconds
        }
    }

    private let payload: Payload
    private var hasBeenConsumed = false

    fileprivate init(
        powerCycleEvidence: PassiveBluetoothExperimentOnePowerCycleEvidence,
        peripheralIdentifier: UUID,
        recorder: PassiveCoreBluetoothCaptureRecorder
    ) {
        payload = Payload(
            admissionIdentity: UUID(),
            powerCycleEvidence: powerCycleEvidence,
            peripheralIdentifier: peripheralIdentifier,
            recorder: recorder,
            issuedAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
    }

    /// Producer-owned read-only staging authority. It exposes no recorder or raw
    /// power-cycle evidence and cannot be read after any alias consumes the handoff.
    func previewForControllerStaging() throws -> StagingPreview {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        return StagingPreview(
            admissionIdentity: payload.admissionIdentity,
            peripheralIdentifier: payload.peripheralIdentifier,
            issuedAtUptimeNanoseconds: payload.issuedAtUptimeNanoseconds
        )
    }

    func consume() throws -> Payload {
        guard !hasBeenConsumed else {
            throw ConsumptionError.alreadyConsumed
        }
        hasBeenConsumed = true
        return payload
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
/// The caller may supply software vehicle context only so contradictory context can fail closed.
/// This ES80-specific authority accepts exactly Nembra's canonical `VehicleProfile.aovoproES80`
/// identity; the deferred MAXSHOT profile or any custom identity cannot originate this run. Matching
/// declared context is still software metadata and is never physical ES80 authentication.
///
/// **Critical integration boundary:** this run and all authority-bearing result types remain
/// package-internal. Raw recorder creation and Experiment One evidence promotion stay producer-file
/// private. The sole widened seam is `issueCaptureAdmission()`: it derives the exact unique target
/// from this run's completed four-window producer, creates this run's recorder, and returns one
/// non-public one-shot handoff. The foreground controller still must consume that handoff and own
/// recorder mutation plus finalized H-bounded artifact issuance before the app can legitimately
/// expose Start/Finish/Share. Physical Experiment One remains blocked.
@MainActor
final class PassiveBluetoothExperimentOneRun {
    let vehicleIdentity: VehicleIdentity
    let powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession

    private var captureRecorder: PassiveCoreBluetoothCaptureRecorder?
    private var captureObservationSeriesIdentity: PassiveBluetoothCandidateObservationSeriesIdentity?

    init(vehicleIdentity: VehicleIdentity) throws {
        guard vehicleIdentity == VehicleProfile.aovoproES80.identity else {
            throw PassiveBluetoothExperimentOneRunError.invalidVehicleContext
        }

        self.vehicleIdentity = VehicleProfile.aovoproES80.identity
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

    /// The only same-module bridge from completed correlation into live capture ownership.
    ///
    /// Callers provide only a local recorder start timestamp. The target UUID, producer authority,
    /// and mutable recorder all come from this exact run. A second call fails because the recorder is
    /// one-shot per run, and the returned admission itself can also be consumed only once.
    func issueCaptureAdmission(
        startedAt: Date = Date()
    ) throws -> PassiveBluetoothExperimentOneCaptureAdmission {
        guard powerCycleObservationSession.result != nil else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleIncomplete
        }
        guard let evidence = completedPowerCycleEvidence else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleAuthorityInvalid
        }
        guard case let .singleRepeatableCandidate(peripheralIdentifier) = evidence.result.correlation.disposition else {
            throw PassiveBluetoothExperimentOneRunError.powerCycleCorrelationNotUnique
        }

        let recorder = try beginCaptureRecorder(startedAt: startedAt)
        return PassiveBluetoothExperimentOneCaptureAdmission(
            powerCycleEvidence: evidence,
            peripheralIdentifier: peripheralIdentifier,
            recorder: recorder
        )
    }

    /// Recorder creation itself remains producer-file private. The reviewed controller bridge must
    /// go through `issueCaptureAdmission()` so a bare caller-selected UUID can never be paired with a
    /// separately-created recorder and promoted as one Experiment One provenance life.
    @discardableResult
    fileprivate func beginCaptureRecorder(
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

    /// Producer-file private for the same reason as recorder creation: no other production file can
    /// wrap mutable/raw capture evidence into Experiment One authority before controller ownership.
    fileprivate func captureEvidenceSnapshot() async throws -> PassiveBluetoothExperimentOneCaptureEvidence {
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

    /// Producer-file private one-shot structural boundary. A later controller-integration slice must
    /// not expose this evaluator until recorder mutation and finalized H-bounded artifact production
    /// are owned by the accepted live controller authority.
    fileprivate func captureEvidenceAssessment() async throws -> PassiveBluetoothExperimentOneCaptureEvidenceAssessment {
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
