#if targetEnvironment(simulator)
@preconcurrency import CoreBluetooth
import Dispatch
import Foundation

/// Explicit Simulator-only presentation scenarios for the real Experiment One coordinator/shell.
///
/// These values are synthetic software QA state. They are compiled out of device builds, never
/// mutate `PassiveBluetoothExperimentOneFieldExecutionGate`, never instantiate a CoreBluetooth
/// controller, and never become capture/protocol/telemetry evidence.
public enum PassiveBluetoothExperimentOneSimulatorQAScenario: String, CaseIterable, Equatable, Sendable {
    case stationaryPreflight = "stationary-preflight"
    case correlationReady = "correlation-ready"
    case correlationObserving = "correlation-observing"
    case correlatedTarget = "correlated-target"
    case rediscoveringTarget = "rediscovering-target"
    case targetReacquired = "target-reacquired"
    case connecting = "connecting"
    case acquiring = "acquiring"
    case observing = "observing"
    case readyToSeal = "ready-to-seal"
    case complete = "complete"
    case failedForeground = "failed-foreground"

    public static let defaultScenario: Self = .stationaryPreflight
}

/// Package-owned deterministic state driver used only by iOS Simulator QA.
///
/// The fixture intentionally reports the real field gate as NO-GO and
/// `physicalProcedurePermitted == false` in every scenario. The app may render these states only
/// after it has obtained a coordinator carrying this package-owned fixture marker. No public API
/// accepts a Boolean that claims field authorization.
@MainActor
final class PassiveBluetoothExperimentOneSimulatorQAFixture {
    private static let syntheticTargetID = UUID(uuidString: "00000000-0000-4000-8000-00000000E580")!

    private(set) var scenario: PassiveBluetoothExperimentOneSimulatorQAScenario
    private(set) var phase: PassiveBluetoothPowerCycleObservationPhase = .firstPoweredOff
    private(set) var completedWindowCount = 0

    init(scenario: PassiveBluetoothExperimentOneSimulatorQAScenario) {
        self.scenario = scenario
        switch scenario {
        case .stationaryPreflight, .correlationReady, .correlationObserving:
            phase = .firstPoweredOff
            completedWindowCount = 0
        default:
            phase = .secondPoweredOn
            completedWindowCount = 4
        }
    }

    var presentationLabel: String {
        "SIMULATOR QA / SYNTHETIC SOFTWARE STATE"
    }

    var status: PassiveBluetoothExperimentOneCoordinator.Status {
        let progressedBeyondCorrelation: Bool
        switch scenario {
        case .stationaryPreflight, .correlationReady, .correlationObserving:
            progressedBeyondCorrelation = false
        default:
            progressedBeyondCorrelation = true
        }

        let progress = PassiveBluetoothPowerCycleObservationProgress(
            phase: phase,
            isAwaitingBluetoothPower: false,
            isAwaitingScanReadiness: false,
            isScanning: scenario == .correlationObserving,
            isSeriesInvalidated: false,
            currentObservedCandidateCount: scenario == .correlationObserving ? 1 : 0,
            completedWindowCount: completedWindowCount
        )

        let correlation: PassiveBluetoothExperimentOneCoordinator.CorrelationStatus =
            progressedBeyondCorrelation ? .singleRepeatableCandidate : .incomplete

        let hasPreparedCaptureAdmission: Bool
        let isCorrelatedTargetRediscovered: Bool
        switch scenario {
        case .rediscoveringTarget:
            hasPreparedCaptureAdmission = true
            isCorrelatedTargetRediscovered = false
        case .targetReacquired:
            hasPreparedCaptureAdmission = true
            isCorrelatedTargetRediscovered = true
        default:
            hasPreparedCaptureAdmission = false
            isCorrelatedTargetRediscovered = false
        }

        let connection: PassiveBluetoothExperimentOneCoordinator.ConnectionStatus
        switch scenario {
        case .connecting:
            connection = .connecting
        case .acquiring, .observing, .readyToSeal:
            connection = .connected
        default:
            connection = .idle
        }

        return PassiveBluetoothExperimentOneCoordinator.Status(
            fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.status,
            physicalProcedurePermitted: false,
            powerCycleProgress: progress,
            correlation: correlation,
            hasPreparedCaptureAdmission: hasPreparedCaptureAdmission,
            isCorrelatedTargetRediscovered: isCorrelatedTargetRediscovered,
            bluetoothState: .poweredOn,
            connection: connection,
            observationReady: scenario == .observing || scenario == .readyToSeal,
            canFinalizeObservationHorizon: scenario == .readyToSeal,
            artifactFinalized: scenario == .complete,
            finalizationCleanup: scenario == .complete ? .complete : .notAttempted,
            foregroundIntegrityLost: scenario == .failedForeground
        )
    }

    var powerCycleResultForPresentation: PassiveBluetoothPowerCycleObservationResult? {
        guard completedWindowCount == 4 else { return nil }
        return try? Self.makeSyntheticPowerCycleResult()
    }

    func startCurrentPowerCycleWindow() throws {
        guard scenario == .stationaryPreflight || scenario == .correlationReady else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowAlreadyActive
        }
        scenario = .correlationObserving
    }

    func finishCurrentPowerCycleWindow() throws -> PassiveBluetoothExperimentOneCoordinator.CorrelationStatus {
        guard scenario == .correlationObserving else {
            throw PassiveBluetoothPowerCycleObservationSessionError.windowNotActive
        }

        completedWindowCount += 1
        if completedWindowCount < PassiveBluetoothPowerCycleObservationPhase.allCases.count {
            phase = PassiveBluetoothPowerCycleObservationPhase(rawValue: completedWindowCount)!
            scenario = .correlationReady
            return .incomplete
        }

        phase = .secondPoweredOn
        scenario = .correlatedTarget
        return .singleRepeatableCandidate
    }

    func confirmCorrelatedTargetAndBeginRediscovery() throws {
        guard scenario == .correlatedTarget else {
            throw PassiveBluetoothExperimentOneCoordinator.CoordinatorError.correlationIncomplete
        }
        // Interactive QA advances immediately to the reacquired state. The dedicated
        // `.rediscoveringTarget` launch scenario preserves that intermediate visual state.
        scenario = .targetReacquired
    }

    func restartPreparedRediscovery() throws {
        guard scenario == .rediscoveringTarget || scenario == .targetReacquired else {
            throw PassiveBluetoothExperimentOneCoordinator.CoordinatorError.captureAdmissionNotPrepared
        }
        scenario = .targetReacquired
    }

    func connectPreparedCapture() throws {
        guard scenario == .targetReacquired else {
            throw PassiveBluetoothExperimentOneCoordinator.CoordinatorError.targetNotRediscovered
        }
        // Interactive QA lands on observation-ready. Dedicated launch scenarios retain
        // connecting/acquiring states for deterministic screenshot coverage.
        scenario = .observing
    }

    func markFinalized() throws -> PassiveBluetoothPowerCycleObservationResult {
        guard scenario == .readyToSeal else {
            throw PassiveBluetoothExperimentOneCoordinator.CoordinatorError.observationNotReady
        }
        let result = try Self.makeSyntheticPowerCycleResult()
        scenario = .complete
        completedWindowCount = 4
        phase = .secondPoweredOn
        return result
    }

    func invalidateForForegroundLoss() {
        scenario = .failedForeground
    }

    private static func makeSyntheticPowerCycleResult() throws -> PassiveBluetoothPowerCycleObservationResult {
        var ledger = PassiveBluetoothPowerCycleObservationLedger(minimumWindowDurationNanoseconds: 1)
        var result: PassiveBluetoothPowerCycleObservationResult?

        for (index, phase) in PassiveBluetoothPowerCycleObservationPhase.allCases.enumerated() {
            let start = UInt64(index * 10 + 1)
            let candidates: [PassiveBluetoothCandidateObservationSnapshot.Candidate]
            if phase.operatorExpectedPowerOn {
                candidates = [
                    PassiveBluetoothCandidateObservationSnapshot.Candidate(
                        id: syntheticTargetID,
                        isConnectable: true
                    )
                ]
            } else {
                candidates = []
            }
            result = try ledger.completeWindow(
                phase: phase,
                startedAtUptimeNanoseconds: start,
                endedAtUptimeNanoseconds: start + 1,
                candidates: candidates
            )
        }

        guard let result else {
            preconditionFailure("Simulator QA fixture must deterministically complete four windows")
        }
        return result
    }
}
#endif
