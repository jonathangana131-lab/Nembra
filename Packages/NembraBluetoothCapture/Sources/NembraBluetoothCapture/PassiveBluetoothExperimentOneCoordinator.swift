@preconcurrency import CoreBluetooth
import Foundation
import NembraCore

/// Pure construction-policy composition for Experiment One coordinator authority.
///
/// A permissive field status is necessary but not sufficient: the coordinator instance must also
/// own the package-constructed canonical live controller. Keeping this composition independent of
/// the current repository gate lets tests prove that a GO status cannot accidentally turn the
/// ordinary public status-only initializer into a second live Bluetooth authority path.
enum PassiveBluetoothExperimentOneCoordinatorConstructionPolicy {
    static func permitsPhysicalProcedure(
        hasCanonicalLiveController: Bool,
        fieldGatePermitsPhysicalProcedure: Bool
    ) -> Bool {
        hasCanonicalLiveController && fieldGatePermitsPhysicalProcedure
    }
}

/// The single app-facing owner for one ES80 Experiment One provenance life.
///
/// App/UI code never receives the mutable recorder, sealed admission, authoritative target UUID,
/// caller-selected vehicle identity, correlation duration, or connection timeout. The package-owned
/// run spans OFF1 -> ON1 -> OFF2 -> ON2 into the same foreground controller that later owns passive
/// GATT acquisition, Ready, Horizon, and immutable finalization.
///
/// Physical execution is subordinate to both the package-owned canonical-controller construction
/// path and an instance-bound `PassiveBluetoothExperimentOneFieldExecutionGate.Status`. The ordinary
/// public initializer is permanently status-only/non-live. Live CoreBluetooth authority can enter
/// only through mechanically gated canonical ES80 factories.
@MainActor
public final class PassiveBluetoothExperimentOneCoordinator {
    public enum CoordinatorError: Error, Equatable, Sendable {
        case physicalProcedureLocked
        case foregroundIntegrityLost
        case captureAdmissionAlreadyPrepared
        case captureAdmissionNotPrepared
        case correlationIncomplete
        case correlationEvidenceInvalid
        case correlationNotUnique
        case targetNotRediscovered
        case targetNotConnectable
        case controllerUnavailable
        case observationNotReady
        case artifactAlreadyFinalized
    }

    public enum CorrelationStatus: Equatable, Sendable {
        case incomplete
        case invalidEvidence
        case noRepeatableCandidate
        case ambiguousRepeatableCandidates(count: Int)
        case singleRepeatableCandidate
    }

    public enum ConnectionStatus: Equatable, Sendable {
        case unavailable
        case idle
        case connecting
        case connected
    }

    /// Post-seal transport cleanup is deliberately distinct from immutable-artifact success.
    /// A cleanup failure can require recovery before another capture, but it cannot retroactively
    /// relabel already-sealed bytes as a failed Horizon artifact.
    public enum FinalizationCleanupStatus: Equatable, Sendable {
        case notAttempted
        case complete
        case failed
    }

    public struct Status: Equatable, Sendable {
        public let fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.Status
        public let physicalProcedurePermitted: Bool
        public let powerCycleProgress: PassiveBluetoothPowerCycleObservationProgress?
        public let correlation: CorrelationStatus
        public let hasPreparedCaptureAdmission: Bool
        public let isCorrelatedTargetRediscovered: Bool
        public let bluetoothState: CBManagerState?
        public let connection: ConnectionStatus
        public let observationReady: Bool
        public let canFinalizeObservationHorizon: Bool
        public let artifactFinalized: Bool
        public let finalizationCleanup: FinalizationCleanupStatus
        public let foregroundIntegrityLost: Bool
    }

    public struct FinalizedArtifact: Equatable, Sendable {
        public let captureJSON: Data
        public let powerCycleResult: PassiveBluetoothPowerCycleObservationResult

        fileprivate init(captureJSON: Data, powerCycleResult: PassiveBluetoothPowerCycleObservationResult) {
            self.captureJSON = captureJSON
            self.powerCycleResult = powerCycleResult
        }
    }

    private let run: PassiveBluetoothExperimentOneRun
    private let controller: ForegroundCoreBluetoothCaptureController?
    private let fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.Status
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?
    private var preparedCorrelatedTargetIdentifier: UUID?
    private var foregroundIntegrityWasLost = false
    private var finalizedArtifactStorage: FinalizedArtifact?
    private var finalizationCleanupStatusStorage: FinalizationCleanupStatus = .notAttempted
    private var experimentHasBegun = false

    /// Canonical ES80 status-only construction.
    ///
    /// This initializer intentionally never creates live CoreBluetooth authority. It stays inert
    /// even when a separately admitted private research build exists, so app code cannot bypass the
    /// canonical factory merely by constructing the coordinator directly.
    public init() throws {
        let identity = VehicleProfile.aovoproES80.identity
        run = try PassiveBluetoothExperimentOneRun(vehicleIdentity: identity)
        controller = nil
        fieldExecutionStatus = PassiveBluetoothExperimentOneFieldExecutionGate.status
    }

    /// Package-only composition seam used by the release-grade canonical ES80 factory.
    /// App code cannot inject a generic controller or bypass field authority through this initializer.
    package init(controller: ForegroundCoreBluetoothCaptureController) throws {
        self.controller = controller
        fieldExecutionStatus = PassiveBluetoothExperimentOneFieldExecutionGate.status
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    /// Package-only composition seam for a capability whose exact instance-bound field status was
    /// already minted by the package gate. This does not accept a Boolean, launch argument, user
    /// preference, imported JSON document, target UUID, or caller-selected vehicle identity.
    package init(
        controller: ForegroundCoreBluetoothCaptureController,
        fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.Status
    ) throws {
        self.controller = controller
        self.fieldExecutionStatus = fieldExecutionStatus
        run = try PassiveBluetoothExperimentOneRun(
            vehicleIdentity: VehicleProfile.aovoproES80.identity
        )
    }

    public var status: Status {
        Status(
            fieldExecutionStatus: fieldExecutionStatus,
            physicalProcedurePermitted: physicalProcedurePermittedForThisCoordinator,
            powerCycleProgress: run.powerCycleObservationSession.progress,
            correlation: correlationStatus,
            hasPreparedCaptureAdmission: pendingCaptureAdmission != nil,
            isCorrelatedTargetRediscovered: isCorrelatedTargetRediscovered,
            bluetoothState: controller?.bluetoothState,
            connection: connectionStatus,
            observationReady: controller?.hasCompleteTargetEvidence ?? false,
            canFinalizeObservationHorizon: controller?.canFinalizeObservationHorizon ?? false,
            artifactFinalized: finalizedArtifactStorage != nil,
            finalizationCleanup: finalizationCleanupStatusStorage,
            foregroundIntegrityLost: foregroundIntegrityWasLost
        )
    }

    /// Immutable evidence is readable for product details/analysis; the mutable producer is not.
    public var powerCycleResult: PassiveBluetoothPowerCycleObservationResult? {
        run.powerCycleObservationSession.result
    }

    public var finalizedArtifact: FinalizedArtifact? {
        finalizedArtifactStorage
    }

    public var lastDiagnostic: String? {
        controller?.lastDiagnostic
    }

    public func startCurrentPowerCycleWindow() throws {
        try requireExecutionAuthority()
        guard finalizedArtifactStorage == nil else { throw CoordinatorError.artifactAlreadyFinalized }
        try run.powerCycleObservationSession.startCurrentWindow()
        experimentHasBegun = true
    }

    @discardableResult
    public func finishCurrentPowerCycleWindow() throws -> CorrelationStatus {
        try requireExecutionAuthority()
        guard finalizedArtifactStorage == nil else { throw CoordinatorError.artifactAlreadyFinalized }
        _ = try run.powerCycleObservationSession.finishCurrentWindow()
        return correlationStatus
    }

    /// Explicit operator confirmation is parameterless. The authoritative full UUID comes only from
    /// this run's four-window evidence. Admission is issued before a fresh scan epoch so controller
    /// acceptance can require a target receipt at/after the producer-owned software handoff.
    public func confirmCorrelatedTargetAndBeginRediscovery() throws {
        try requireExecutionAuthority()
        guard pendingCaptureAdmission == nil else { throw CoordinatorError.captureAdmissionAlreadyPrepared }
        guard let result = run.powerCycleObservationSession.result else { throw CoordinatorError.correlationIncomplete }
        switch result.correlation.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            throw CoordinatorError.correlationEvidenceInvalid
        case .noRepeatableCandidate, .ambiguousRepeatableCandidates:
            throw CoordinatorError.correlationNotUnique
        case .singleRepeatableCandidate:
            break
        }
        guard let evidence = run.completedPowerCycleEvidence,
              case let .singleRepeatableCandidate(identifier) = evidence.result.correlation.disposition else {
            throw CoordinatorError.correlationNotUnique
        }
        guard let controller else { throw CoordinatorError.controllerUnavailable }

        let admission = try run.issueCaptureAdmission()
        pendingCaptureAdmission = admission
        preparedCorrelatedTargetIdentifier = identifier
        try controller.startScanning(captureAdvertisementCadence: true)
    }

    /// Reopens only the rediscovery scan for the same already-issued admission. No new recorder is minted.
    public func restartPreparedRediscovery() throws {
        try requireExecutionAuthority()
        guard pendingCaptureAdmission != nil,
              preparedCorrelatedTargetIdentifier != nil else {
            throw CoordinatorError.captureAdmissionNotPrepared
        }
        guard let controller else { throw CoordinatorError.controllerUnavailable }
        try controller.startScanning(captureAdvertisementCadence: true)
    }

    /// Consumes the hidden admission only after the hidden exact UUID appears in the post-admission
    /// catalog. No UUID or timeout is caller-selectable. A staging failure remains retryable only
    /// while producer `previewForControllerStaging()` proves this exact admission is still unconsumed.
    public func connectPreparedCapture() throws {
        try requireExecutionAuthority()
        guard let admission = pendingCaptureAdmission,
              let identifier = preparedCorrelatedTargetIdentifier else {
            throw CoordinatorError.captureAdmissionNotPrepared
        }
        guard let controller else { throw CoordinatorError.controllerUnavailable }
        guard controller.hasDiscoveredPeripheral(identifier: identifier),
              let discovery = controller.discoveredPeripheral(identifier: identifier) else {
            throw CoordinatorError.targetNotRediscovered
        }
        guard discovery.isConnectable != false else { throw CoordinatorError.targetNotConnectable }

        do {
            try controller.connectUsingExperimentOneAdmission(admission, timeout: 12)
            pendingCaptureAdmission = nil
            preparedCorrelatedTargetIdentifier = nil
        } catch {
            // The narrowed producer staging preview remains readable only before
            // irreversible one-shot consumption. Preserve the same completed
            // OFF/ON evidence life only while that exact authority still exists.
            do {
                _ = try admission.previewForControllerStaging()
            } catch PassiveBluetoothExperimentOneCaptureAdmission.ConsumptionError.alreadyConsumed {
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
            } catch {
                // Unknown/future staging-state failures are not proven retryable.
                pendingCaptureAdmission = nil
                preparedCorrelatedTargetIdentifier = nil
            }
            throw error
        }
    }

    @discardableResult
    public func finalizeObservationHorizon() async throws -> FinalizedArtifact {
        try requireExecutionAuthority()
        guard finalizedArtifactStorage == nil else { throw CoordinatorError.artifactAlreadyFinalized }
        guard let controller else { throw CoordinatorError.controllerUnavailable }
        guard controller.canFinalizeObservationHorizon else { throw CoordinatorError.observationNotReady }
        guard let result = run.powerCycleObservationSession.result else { throw CoordinatorError.correlationIncomplete }

        let data = try await controller.encodedFinalizedObservationHorizonJSON(prettyPrinted: true)
        let artifact = FinalizedArtifact(captureJSON: data, powerCycleResult: result)

        // Once controller finalization returns, these exact bytes have crossed immutable Horizon.
        // Publish that truth before fallible transport cleanup so cleanup cannot retroactively turn a
        // legitimate artifact into a seal failure. Cleanup outcome remains separately observable.
        finalizedArtifactStorage = artifact
        do {
            try controller.teardownActiveConnectionAfterFinalization()
            finalizationCleanupStatusStorage = .complete
        } catch {
            finalizationCleanupStatusStorage = .failed
        }
        return artifact
    }

    /// Destructive safety paths remain available regardless of GO because they cannot create authority.
    public func abandonExperiment() {
        if run.powerCycleObservationSession.result == nil {
            run.powerCycleObservationSession.abandonCurrentWindow()
        }
        controller?.stopScanning()
        controller?.cancelActiveConnection()
        pendingCaptureAdmission = nil
        preparedCorrelatedTargetIdentifier = nil
    }

    public func invalidateForForegroundLoss() {
        guard finalizedArtifactStorage == nil, experimentHasBegun else { return }
        foregroundIntegrityWasLost = true
        if run.powerCycleObservationSession.result == nil {
            run.powerCycleObservationSession.abandonCurrentWindow()
        }
        controller?.invalidateActiveCaptureForForegroundLoss()
        controller?.stopScanning()
        pendingCaptureAdmission = nil
        preparedCorrelatedTargetIdentifier = nil
    }

    private var correlationStatus: CorrelationStatus {
        guard let result = run.powerCycleObservationSession.result else { return .incomplete }
        switch result.correlation.disposition {
        case .invalidObservationAuthority, .invalidObservationWindowOrder:
            return .invalidEvidence
        case .noRepeatableCandidate:
            return .noRepeatableCandidate
        case let .ambiguousRepeatableCandidates(ids):
            return .ambiguousRepeatableCandidates(count: ids.count)
        case .singleRepeatableCandidate:
            return .singleRepeatableCandidate
        }
    }

    private var isCorrelatedTargetRediscovered: Bool {
        guard let identifier = preparedCorrelatedTargetIdentifier,
              pendingCaptureAdmission != nil,
              let controller else { return false }
        return controller.hasDiscoveredPeripheral(identifier: identifier)
    }

    private var connectionStatus: ConnectionStatus {
        guard let controller else { return .unavailable }
        switch controller.connectionPhase {
        case .idle: return .idle
        case .connecting(_): return .connecting
        case .connected(_): return .connected
        }
    }

    private var physicalProcedurePermittedForThisCoordinator: Bool {
        PassiveBluetoothExperimentOneCoordinatorConstructionPolicy.permitsPhysicalProcedure(
            hasCanonicalLiveController: controller != nil,
            fieldGatePermitsPhysicalProcedure: PassiveBluetoothExperimentOneFieldExecutionGate
                .permitsPhysicalProcedure(status: fieldExecutionStatus)
        )
    }

    private func requireExecutionAuthority() throws {
        guard physicalProcedurePermittedForThisCoordinator else {
            throw CoordinatorError.physicalProcedureLocked
        }
        guard !foregroundIntegrityWasLost else { throw CoordinatorError.foregroundIntegrityLost }
    }
}
