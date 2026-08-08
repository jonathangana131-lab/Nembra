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
        case captureAdmissionAlreadyPrepared
        case captureAdmissionNotPrepared
        case correlatedTargetUnavailable
        case targetNotRediscovered(UUID)
        case targetNotConnectable(UUID)
    }

    public let controller: ForegroundCoreBluetoothCaptureController

    /// The only public correlation producer for this Experiment One life. The underlying run owns
    /// this exact instance; app code must not create a second producer and splice its result in.
    public var powerCycleObservationSession: PassiveBluetoothPowerCycleObservationSession {
        run.powerCycleObservationSession
    }

    /// Descriptive target identity for the currently prepared handoff. This UUID is not mutation
    /// authority; the retained package-internal admission remains the sole capture ownership permit.
    public private(set) var preparedCorrelatedTargetIdentifier: UUID?

    public var hasPreparedCaptureAdmission: Bool {
        pendingCaptureAdmission != nil
    }

    private let run: PassiveBluetoothExperimentOneRun
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?

    /// Experiment One is ES80-specific. Canonical vehicle context is selected inside the package,
    /// never injected by app/UI code merely to make a run eligible.
    public init(controller: ForegroundCoreBluetoothCaptureController) throws {
        self.controller = controller
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    /// Creates the complete app-facing ES80 Experiment One software owner. Both the
    /// controller and run are minted inside this package boundary so SwiftUI cannot
    /// splice a separately-created generic controller into field provenance.
    public convenience init() throws {
        let controller = try ForegroundCoreBluetoothCaptureController(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
        try self.init(controller: controller)
    }

    /// Seals completed four-window correlation into this run's exact one-shot capture admission,
    /// then opens a new controller scan epoch. `startScanning` clears the controller's candidate
    /// catalog synchronously, so any target later accepted by `connectPreparedCapture` was received
    /// after this admission was issued rather than replayed from pre-admission catalog state.
    ///
    /// If scan startup is temporarily unavailable, the already-issued admission remains retained and
    /// `restartPreparedRediscovery()` may be called later. No second recorder/admission is minted.
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

    /// Starts another fresh controller scan epoch for the same already-issued admission. This does
    /// not mint a new recorder or alter the four-window evidence authority.
    public func restartPreparedRediscovery() throws {
        guard pendingCaptureAdmission != nil,
              preparedCorrelatedTargetIdentifier != nil else {
            throw CoordinatorError.captureAdmissionNotPrepared
        }
        try controller.startScanning(captureAdvertisementCadence: true)
    }

    /// Consumes the retained admission only after the exact correlated UUID has reappeared in the
    /// controller catalog created after admission issuance. Calling this too early therefore fails
    /// without consuming the one-shot handoff.
    ///
    /// Once controller consumption is attempted, this coordinator clears its local admission even
    /// if the controller fails: downstream failures may have consumed package authority, so retrying
    /// the same opaque handoff would be ambiguous. A new Experiment One run is the fail-closed path.
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
        } catch let error as ForegroundCoreBluetoothCaptureController.ControllerError {
            // These failures happen before the controller's irreversible admission.consume().
            // Preserve the same sealed evidence life so passive scanning / terminal-callback
            // recovery can continue without forcing the rider to repeat four valid windows.
            switch error {
            case .unknownPeripheral,
                 .peripheralNotConnectable,
                 .peripheralAwaitingTerminalCallback:
                throw error
            default:
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
                throw error
            }
        } catch {
            // Unknown downstream failure may have crossed the one-shot handoff. Fail closed.
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
            throw error
        }

        pendingCaptureAdmission = nil
        preparedCorrelatedTargetIdentifier = nil
    }
}
