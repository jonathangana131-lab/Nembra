@preconcurrency import CoreBluetooth
import Foundation
import NembraCore

/// App-facing, ES80-specific composition of the accepted Experiment One evidence producers.
///
/// This coordinator is deliberately narrower than the public research primitives. It owns one
/// package-issued four-window correlation run and, only when the repository field gate permits it,
/// one foreground capture controller. It never accepts a peripheral UUID, recorder, observation
/// snapshot, or admission token from app/UI code. The correlated full CoreBluetooth UUID remains
/// package-owned mutation authority.
///
/// Physical execution is additionally locked by `PassiveBluetoothExperimentOneFieldExecutionGate`.
/// The current repository gate is NO-GO, so construction does not even create the live foreground
/// CoreBluetooth controller and every procedure-advancing method fails before starting Bluetooth
/// work. Opening that gate later still does not authenticate an ES80 or assign protocol meaning;
/// it only authorizes the exact accepted software procedure for a final accepted field build.
@MainActor
public final class PassiveBluetoothExperimentOneCoordinator {
    public enum CoordinatorError: Error, Equatable, Sendable {
        case physicalProcedureLocked
        case foregroundIntegrityLost
        case correlationIncomplete
        case correlationEvidenceInvalid
        case correlationNotUnique
        case correlatedTargetConfirmationRequired
        case passiveDiscoveryRequired
        case correlatedTargetNotRediscovered
        case correlatedTargetNotConnectable
        case controllerNotReadyForAdmission
        case observationNotReady
        case artifactAlreadyFinalized
    }

    /// Public correlation state intentionally omits the authoritative peripheral UUID.
    /// The app may present one deterministic signal result without becoming a second target owner.
    public enum CorrelationStatus: Equatable, Sendable {
        case incomplete
        case invalidEvidence
        case noRepeatableCandidate
        case ambiguousRepeatableCandidates(count: Int)
        case singleRepeatableCandidate
    }

    /// Sanitized transport state for product presentation. The selected UUID remains package-owned.
    public enum ConnectionStatus: Equatable, Sendable {
        case idle
        case connecting
        case connected
    }

    /// Immutable result issued only after this coordinator has driven the exact sealed admission
    /// into the foreground controller and that controller has frozen a valid terminal Horizon.
    ///
    /// `captureJSON` preserves the exact controller-produced artifact bytes. `powerCycleResult`
    /// preserves the immutable four-window evidence from the same package-owned run. A future
    /// manifest-schema owner may encode these into one durable envelope; app code cannot construct
    /// this authority-bearing value itself.
    public struct FinalizedArtifact: Equatable, Sendable {
        public let captureJSON: Data
        public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult

        fileprivate init(
            captureJSON: Data,
            powerCycleResult: PassiveBluetoothPowerCycleObservationResult
        ) {
            self.captureJSON = captureJSON
            self.powerCycleResult = powerCycleResult
        }
    }

    public struct Status: Equatable, Sendable {
        public let physicalProcedurePermitted: Bool
        public let physicalProcedureStatus: PassiveBluetoothExperimentOneFieldExecutionGate.Status
        public let powerCycleProgress: PassiveBluetoothPowerCycleObservationProgress?
        public let correlation: CorrelationStatus
        public let isCorrelatedTargetConfirmed: Bool
        public let isCorrelatedTargetRediscovered: Bool
        public let connection: ConnectionStatus
        public let observationReady: Bool
        public let canFinalizeObservationHorizon: Bool
        public let artifactFinalized: Bool
        public let artifactSealedButTransportTeardownFailed: Bool
        public let foregroundIntegrityLost: Bool
    }

    private let run: PassiveBluetoothExperimentOneRun
    private let controller: ForegroundCoreBluetoothCaptureController?
    private var correlatedTargetConfirmed = false
    private var passiveDiscoveryStarted = false
    private var experimentHasBegun = false
    private var foregroundIntegrityWasLost = false
    private var sealedArtifact: FinalizedArtifact?
    private var sealedArtifactTransportTeardownFailed = false

    /// Creates one canonical AOVOPRO ES80 Experiment One software life.
    /// No caller-selected vehicle identity or peripheral target can enter this path.
    public init() throws {
        let canonicalIdentity = VehicleProfile.aovoproES80.identity
        run = try PassiveBluetoothExperimentOneRun(vehicleIdentity: canonicalIdentity)
        if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure {
            controller = try ForegroundCoreBluetoothCaptureController(
                vehicleIdentity: canonicalIdentity
            )
        } else {
            controller = nil
        }
    }

    public var status: Status {
        Status(
            physicalProcedurePermitted: PassiveBluetoothExperimentOneFieldExecutionGate
                .permitsPhysicalProcedure,
            physicalProcedureStatus: PassiveBluetoothExperimentOneFieldExecutionGate.status,
            powerCycleProgress: run.powerCycleObservationSession.progress,
            correlation: correlationStatus,
            isCorrelatedTargetConfirmed: correlatedTargetConfirmed,
            isCorrelatedTargetRediscovered: isCorrelatedTargetRediscovered,
            connection: connectionStatus,
            observationReady: controller?.hasCompleteTargetEvidence ?? false,
            canFinalizeObservationHorizon: controller?.canFinalizeObservationHorizon ?? false,
            artifactFinalized: sealedArtifact != nil,
            artifactSealedButTransportTeardownFailed: sealedArtifactTransportTeardownFailed,
            foregroundIntegrityLost: foregroundIntegrityWasLost
        )
    }

    public var finalizedArtifact: FinalizedArtifact? {
        sealedArtifact
    }

    /// Starts the next fixed-duration OFF1 -> ON1 -> OFF2 -> ON2 window.
    /// The package-owned run fixes the accepted duration; the app cannot shorten it.
    public func startCurrentPowerCycleWindow() throws {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }

        try run.powerCycleObservationSession.startCurrentWindow()
        experimentHasBegun = true
    }

    /// Finishes the current bounded window and returns only a UUID-free product correlation state.
    /// Raw immutable evidence remains owned by the run and is attached to `FinalizedArtifact` only
    /// after the same run's sealed capture admission reaches terminal H.
    @discardableResult
    public func finishCurrentPowerCycleWindow() throws -> CorrelationStatus {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }

        _ = try run.powerCycleObservationSession.finishCurrentWindow()
        return correlationStatus
    }

    /// Operator abandonment is always permitted as a safety action, including while the repository
    /// field gate is closed. It can only invalidate evidence; it can never create authority.
    public func abandonExperiment() {
        if run.powerCycleObservationSession.result == nil {
            run.powerCycleObservationSession.abandonCurrentWindow()
        }
        controller?.stopScanning()
        controller?.cancelActiveConnection()
        experimentHasBegun = false
    }

    /// Explicitly confirms the single repeated signal after all four accepted windows.
    /// No UUID is accepted from the caller. Confirmation is local software intent only and does not
    /// upgrade the signal into authenticated ES80 identity.
    public func confirmCorrelatedTarget() throws {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }
        guard run.powerCycleObservationSession.result != nil else {
            throw CoordinatorError.correlationIncomplete
        }

        switch correlationStatus {
        case .singleRepeatableCandidate:
            correlatedTargetConfirmed = true
        case .invalidEvidence:
            throw CoordinatorError.correlationEvidenceInvalid
        case .incomplete:
            throw CoordinatorError.correlationIncomplete
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw CoordinatorError.correlationNotUnique
        }
    }

    /// Begins a fresh controller-owned passive rediscovery catalog only after explicit confirmation.
    /// The coordinator does not connect by name/RSSI/service hints and does not expose the target UUID.
    public func startPassiveRediscovery() throws {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard correlatedTargetConfirmed else {
            throw CoordinatorError.correlatedTargetConfirmationRequired
        }
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }
        guard let controller else {
            throw CoordinatorError.controllerNotReadyForAdmission
        }

        try controller.startScanning(captureAdvertisementCadence: false)
        passiveDiscoveryStarted = true
    }

    /// Consumes the run-issued one-shot admission only when the exact correlated full UUID is already
    /// present in this controller's current discovery catalog and is not explicitly non-connectable.
    ///
    /// This method is intentionally parameterless. App/UI code cannot choose a nearby peripheral or
    /// splice a UUID learned from another experiment into the accepted evidence life.
    public func connectRediscoveredCorrelatedTarget() throws {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard correlatedTargetConfirmed else {
            throw CoordinatorError.correlatedTargetConfirmationRequired
        }
        guard passiveDiscoveryStarted else {
            throw CoordinatorError.passiveDiscoveryRequired
        }
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }
        guard let controller else {
            throw CoordinatorError.controllerNotReadyForAdmission
        }
        guard let correlatedIdentifier = correlatedPeripheralIdentifier else {
            throw CoordinatorError.correlationNotUnique
        }
        guard let discovery = controller.discoveredPeripherals.first(where: {
            $0.id == correlatedIdentifier
        }) else {
            throw CoordinatorError.correlatedTargetNotRediscovered
        }
        guard discovery.isConnectable != false else {
            throw CoordinatorError.correlatedTargetNotConnectable
        }

        // These synchronous MainActor checks mirror the controller's non-admission-consuming
        // preconditions. No actor hop occurs between them, admission issuance, and consumption, so
        // a Bluetooth callback cannot interleave and burn the run's one-shot recorder prematurely.
        guard controller.bluetoothState == .poweredOn,
              controller.connectionPhase == .idle,
              !controller.hasTargetSession,
              !controller.captureFailed else {
            throw CoordinatorError.controllerNotReadyForAdmission
        }

        let admission = try run.issueCaptureAdmission()
        try controller.connectUsingExperimentOneAdmission(admission)
        passiveDiscoveryStarted = false
    }

    /// Freezes and returns the immutable terminal-H capture from the same run that issued correlation
    /// and admission. Intermediate rendered time/UI state is not authority; the controller enforces
    /// its accepted monotonic Ready -> H duration permit immediately before mutation.
    @discardableResult
    public func finalizeObservationHorizon() async throws -> FinalizedArtifact {
        try requirePhysicalProcedurePermit()
        try requireForegroundIntegrity()
        guard sealedArtifact == nil else {
            throw CoordinatorError.artifactAlreadyFinalized
        }
        guard let controller else {
            throw CoordinatorError.controllerNotReadyForAdmission
        }
        guard controller.canFinalizeObservationHorizon else {
            throw CoordinatorError.observationNotReady
        }
        guard let powerCycleResult = run.powerCycleObservationSession.result else {
            throw CoordinatorError.correlationIncomplete
        }

        let captureJSON = try await controller.encodedFinalizedObservationHorizonJSON(
            prettyPrinted: true
        )
        let artifact = FinalizedArtifact(
            captureJSON: captureJSON,
            powerCycleResult: powerCycleResult
        )
        // The artifact is already immutable here. Do not erase that truth if fallible transport
        // teardown subsequently fails; expose the sealed result and a separate recovery diagnostic.
        sealedArtifact = artifact
        do {
            try controller.teardownActiveConnectionAfterFinalization()
        } catch {
            sealedArtifactTransportTeardownFailed = true
        }
        return artifact
    }

    /// Scene/background loss invalidates any in-progress Experiment One evidence life and remains
    /// callable even when field execution is locked. A terminal sealed artifact stays immutable.
    public func invalidateForForegroundLoss() {
        guard sealedArtifact == nil, experimentHasBegun else { return }
        foregroundIntegrityWasLost = true
        if run.powerCycleObservationSession.result == nil {
            run.powerCycleObservationSession.abandonCurrentWindow()
        }
        controller?.invalidateActiveCaptureForForegroundLoss()
        controller?.stopScanning()
    }

    private var correlationStatus: CorrelationStatus {
        guard let result = run.powerCycleObservationSession.result else {
            return .incomplete
        }
        switch result.correlation.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            return .invalidEvidence
        case .noRepeatableCandidate:
            return .noRepeatableCandidate
        case let .ambiguousRepeatableCandidates(identifiers):
            return .ambiguousRepeatableCandidates(count: identifiers.count)
        case .singleRepeatableCandidate:
            return .singleRepeatableCandidate
        }
    }

    private var correlatedPeripheralIdentifier: UUID? {
        guard let evidence = run.completedPowerCycleEvidence,
              case let .singleRepeatableCandidate(identifier) =
                evidence.result.correlation.disposition else {
            return nil
        }
        return identifier
    }

    private var isCorrelatedTargetRediscovered: Bool {
        guard correlatedTargetConfirmed,
              passiveDiscoveryStarted,
              let correlatedPeripheralIdentifier,
              let controller else {
            return false
        }
        return controller.discoveredPeripherals.contains {
            $0.id == correlatedPeripheralIdentifier
        }
    }

    private var connectionStatus: ConnectionStatus {
        guard let controller else { return .idle }
        switch controller.connectionPhase {
        case .idle:
            return .idle
        case .connecting(_):
            return .connecting
        case .connected(_):
            return .connected
        }
    }

    private func requirePhysicalProcedurePermit() throws {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CoordinatorError.physicalProcedureLocked
        }
    }

    private func requireForegroundIntegrity() throws {
        guard !foregroundIntegrityWasLost else {
            throw CoordinatorError.foregroundIntegrityLost
        }
    }
}
