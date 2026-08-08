@preconcurrency import CoreBluetooth
import Foundation
import NembraCore

/// The single app-facing owner for one ES80 Experiment One provenance life.
///
/// App/UI code never receives the mutable recorder, sealed admission, authoritative target UUID,
/// caller-selected vehicle identity, correlation duration, or connection timeout. The package-owned
/// run spans OFF1 -> ON1 -> OFF2 -> ON2 into the same foreground controller that later owns passive
/// GATT acquisition, Ready, Horizon, and immutable finalization.
///
/// Physical execution is subordinate to `PassiveBluetoothExperimentOneFieldExecutionGate`.
/// While the repository gate is NO-GO this type does not instantiate a live CoreBluetooth capture
/// controller and every procedure-advancing API fails before Bluetooth work begins.
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
    private var pendingCaptureAdmission: PassiveBluetoothExperimentOneCaptureAdmission?
    private var preparedCorrelatedTargetIdentifier: UUID?
    private var foregroundIntegrityWasLost = false
    private var finalizedArtifactStorage: FinalizedArtifact?
    private var experimentHasBegun = false

    /// Canonical ES80 only. No caller-selected vehicle/controller can enter the field authority path.
    public init() throws {
        let identity = VehicleProfile.aovoproES80.identity
        run = try PassiveBluetoothExperimentOneRun(vehicleIdentity: identity)
        if PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure {
            controller = try ForegroundCoreBluetoothCaptureController(vehicleIdentity: identity)
        } else {
            controller = nil
        }
    }

    public var status: Status {
        Status(
            fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.status,
            physicalProcedurePermitted: PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure,
            powerCycleProgress: run.powerCycleObservationSession.progress,
            correlation: correlationStatus,
            hasPreparedCaptureAdmission: pendingCaptureAdmission != nil,
            isCorrelatedTargetRediscovered: isCorrelatedTargetRediscovered,
            bluetoothState: controller?.bluetoothState,
            connection: connectionStatus,
            observationReady: controller?.hasCompleteTargetEvidence ?? false,
            canFinalizeObservationHorizon: controller?.canFinalizeObservationHorizon ?? false,
            artifactFinalized: finalizedArtifactStorage != nil,
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
        guard let discovery = controller.discoveredPeripherals.first(where: { $0.id == identifier }) else {
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
        finalizedArtifactStorage = artifact
        try? controller.teardownActiveConnectionAfterFinalization()
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
        return controller.discoveredPeripherals.contains { $0.id == identifier }
    }

    private var connectionStatus: ConnectionStatus {
        guard let controller else { return .unavailable }
        switch controller.connectionPhase {
        case .idle: return .idle
        case .connecting(_): return .connecting
        case .connected(_): return .connected
        }
    }

    private func requireExecutionAuthority() throws {
        guard PassiveBluetoothExperimentOneFieldExecutionGate.permitsPhysicalProcedure else {
            throw CoordinatorError.physicalProcedureLocked
        }
        guard !foregroundIntegrityWasLost else { throw CoordinatorError.foregroundIntegrityLost }
    }
}
