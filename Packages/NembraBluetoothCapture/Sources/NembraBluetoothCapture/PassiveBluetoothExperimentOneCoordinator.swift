import Foundation

/// App-facing owner for one truthful Experiment One provenance life.
///
/// SwiftUI may drive the public four-window observation session exposed here, but it never receives
/// the package-internal capture admission, mutable recorder, caller-selected vehicle identity, or
/// any caller-mintable authority token. After correlation completes, this coordinator issues the
/// sealed admission itself, immediately starts a fresh controller scan (which clears the controller
/// candidate catalog), retains the admission while the exact correlated UUID is rediscovered, and
/// only then permits the foreground controller to consume that same one-shot admission.
///
/// This is software callback/provenance authority only. A repeated CoreBluetooth UUID remains a
/// correlated Bluetooth target, not authenticated AOVOPRO ES80 identity or RF emission-time proof.
@MainActor
public final class PassiveBluetoothExperimentOneCoordinator {
    public enum CoordinatorError: Error, Equatable, Sendable {
        case fieldExecutionNotAuthorized
        case captureAdmissionAlreadyPrepared
        case captureAdmissionNotPrepared
        case correlatedTargetUnavailable
        case targetNotRediscovered(UUID)
        case targetNotConnectable(UUID)
    }

    public let controller: ForegroundCoreBluetoothCaptureController

    public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession {
        run.powerCycleObservationSession
    }

    public private(set) var preparedCorrelatedTargetIdentifier: UUID?

    public var hasPreparedCaptureAdmission: Bool {
        pendingCaptureAdmission != nil
    }

    private let run: PassiveBluetoothExperimentOneRun
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?

    /// Package-only deterministic composition seam. Product UI cannot inject a generic controller
    /// and call that a field-authorized Experiment One. Public production construction is owned by
    /// `makeAuthorizedES80()` in the canonical-ES80 extension and is mechanically gated there.
    package init(controller: ForegroundCoreBluetoothCaptureController) throws {
        self.controller = controller
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    public func prepareCaptureRediscovery(
        startedAt: Date = Date()
    ) throws {
        guard pendingCaptureAdmission == nil else {
            throw CoordinatorError.captureAdmissionAlreadyPrepared
        }
        guard let evidence = run.completedPowerCycleEvidence,
              case let .singleRepeatableCandidate(identifier) = evidence.result.correlation.disposition else {
            throw CoordinatorError.correlatedTargetUnavailable
        }

        let admission = try run.issueCaptureAdmission(startedAt: startedAt)
        pendingCaptureAdmission = admission
        preparedCorrelatedTargetIdentifier = identifier

        try restartPreparedRediscovery()
    }

    public func restartPreparedRediscovery() throws {
        guard pendingCaptureAdmission != nil,
              preparedCorrelatedTargetIdentifier != nil else {
            throw CoordinatorError.captureAdmissionNotPrepared
        }
        try controller.startScanning(captureAdvertisementCadence: true)
    }

    public func connectPreparedCapture(
        timeout: TimeInterval = 12
    ) throws {
        guard let admission = pendingCaptureAdmission,
              let identifier = preparedCorrelatedTargetIdentifier else {
            throw CoordinatorError.captureAdmissionNotPrepared
        }
        guard let discovery = controller.discoveredPeripherals.first(where: { $0.id == identifier }) else {
            throw CoordinatorError.targetNotRediscovered(identifier)
        }
        if discovery.isConnectable == false {
            throw CoordinatorError.targetNotConnectable(identifier)
        }

        do {
            try controller.connectUsingExperimentOneAdmission(admission, timeout: timeout)
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
        } catch {
            if (try? admission.stagingPreview()) == nil {
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
            }
            throw error
        }
    }
}