#if DEBUG && targetEnvironment(simulator)
/// Deterministic, presentation-only Experiment One states for iOS Simulator acceptance.
///
/// This fixture is compiled only into Debug iOS Simulator builds. It never constructs the live
/// capture coordinator, never owns Bluetooth transport, never creates capture evidence, and never
/// changes the package-owned physical execution gate. Every snapshot is explicitly labeled
/// SIMULATOR / QA so rendered states cannot be mistaken for measured or physical ES80 evidence.
///
/// App integration may select one of these finite scenarios to exercise the real Capture views,
/// accessibility tree, screenshots, and recovery copy. Selecting a scenario is not authorization:
/// the physical gate remains NO-GO in every snapshot.
@MainActor
public final class PassiveBluetoothExperimentOneSimulatorQAFixture {
    public static let evidenceLabel = "SIMULATOR / QA"
    public static let recipeID = PassiveBluetoothExperimentOneFieldExecutionGate.recipeID

    public enum Scenario: String, CaseIterable, Sendable {
        case stationaryPreflight
        case firstPoweredOff
        case firstPoweredOn
        case secondPoweredOff
        case secondPoweredOn
        case targetConfirmation
        case passiveDiscovery
        case observationReady
        case horizonSealed
        case captureComplete
        case shareRetry
        case foregroundInterrupted
    }

    /// The finite successful path. Interruption is an alternate adversarial scenario and is never
    /// appended after a legitimately completed Share flow.
    public static let happyPathScenarios: [Scenario] = [
        .stationaryPreflight,
        .firstPoweredOff,
        .firstPoweredOn,
        .secondPoweredOff,
        .secondPoweredOn,
        .targetConfirmation,
        .passiveDiscovery,
        .observationReady,
        .horizonSealed,
        .captureComplete,
        .shareRetry,
    ]

    public enum ArtifactState: Equatable, Sendable {
        case unavailable
        case sealed
        case completeReadyForAnalysis
        case shareRetry
        case invalidated
    }

    public struct Snapshot: Equatable, Sendable {
        public let scenario: Scenario
        public let evidenceLabel: String
        public let recipeID: PassiveBluetoothExperimentRecipeID
        public let fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.Status
        public let physicalProcedurePermitted: Bool
        public let mayUseBluetoothTransport: Bool
        public let correlation: PassiveBluetoothExperimentOneCoordinator.CorrelationStatus
        public let connection: PassiveBluetoothExperimentOneCoordinator.ConnectionStatus
        public let hasPreparedCaptureAdmission: Bool
        public let isCorrelatedTargetRediscovered: Bool
        public let observationReady: Bool
        public let canFinalizeObservationHorizon: Bool
        public let artifactState: ArtifactState
        public let title: String
        public let accessibilitySummary: String
    }

    public private(set) var scenario: Scenario

    private init(scenario: Scenario) {
        self.scenario = scenario
    }

    public static func make(
        scenario: Scenario = .stationaryPreflight
    ) -> PassiveBluetoothExperimentOneSimulatorQAFixture {
        PassiveBluetoothExperimentOneSimulatorQAFixture(scenario: scenario)
    }

    public var snapshot: Snapshot {
        Self.snapshot(for: scenario)
    }

    /// Advances only the finite presentation script. The physical gate stays NO-GO and no transport
    /// or evidence producer is created.
    @discardableResult
    public func advance() -> Snapshot {
        guard let index = Self.happyPathScenarios.firstIndex(of: scenario),
              Self.happyPathScenarios.indices.contains(index + 1) else {
            return snapshot
        }
        scenario = Self.happyPathScenarios[index + 1]
        return snapshot
    }

    @discardableResult
    public func reset() -> Snapshot {
        scenario = .stationaryPreflight
        return snapshot
    }

    /// Produces a closed-world UI fixture. Caller selection changes presentation only and can never
    /// turn this value into field authority or legitimate capture evidence.
    public static func snapshot(for scenario: Scenario) -> Snapshot {
        Snapshot(
            scenario: scenario,
            evidenceLabel: evidenceLabel,
            recipeID: recipeID,
            fieldExecutionStatus: PassiveBluetoothExperimentOneFieldExecutionGate.status,
            physicalProcedurePermitted: false,
            mayUseBluetoothTransport: false,
            correlation: correlation(for: scenario),
            connection: connection(for: scenario),
            hasPreparedCaptureAdmission: hasPreparedCaptureAdmission(for: scenario),
            isCorrelatedTargetRediscovered: isCorrelatedTargetRediscovered(for: scenario),
            observationReady: observationReady(for: scenario),
            canFinalizeObservationHorizon: scenario == .observationReady,
            artifactState: artifactState(for: scenario),
            title: title(for: scenario),
            accessibilitySummary: accessibilitySummary(for: scenario)
        )
    }

    private static func correlation(
        for scenario: Scenario
    ) -> PassiveBluetoothExperimentOneCoordinator.CorrelationStatus {
        switch scenario {
        case .stationaryPreflight,
             .firstPoweredOff,
             .firstPoweredOn,
             .secondPoweredOff:
            return .incomplete
        case .secondPoweredOn,
             .targetConfirmation,
             .passiveDiscovery,
             .observationReady,
             .horizonSealed,
             .captureComplete,
             .shareRetry:
            return .singleRepeatableCandidate
        case .foregroundInterrupted:
            return .invalidEvidence
        }
    }

    private static func connection(
        for scenario: Scenario
    ) -> PassiveBluetoothExperimentOneCoordinator.ConnectionStatus {
        switch scenario {
        case .passiveDiscovery:
            return .connecting
        case .observationReady:
            return .connected
        case .foregroundInterrupted:
            return .unavailable
        default:
            return .idle
        }
    }

    private static func hasPreparedCaptureAdmission(for scenario: Scenario) -> Bool {
        switch scenario {
        case .targetConfirmation, .passiveDiscovery:
            return true
        default:
            return false
        }
    }

    private static func isCorrelatedTargetRediscovered(for scenario: Scenario) -> Bool {
        switch scenario {
        case .passiveDiscovery:
            return true
        default:
            return false
        }
    }

    private static func observationReady(for scenario: Scenario) -> Bool {
        switch scenario {
        case .observationReady,
             .horizonSealed,
             .captureComplete,
             .shareRetry:
            return true
        default:
            return false
        }
    }

    private static func artifactState(for scenario: Scenario) -> ArtifactState {
        switch scenario {
        case .horizonSealed:
            return .sealed
        case .captureComplete:
            return .completeReadyForAnalysis
        case .shareRetry:
            return .shareRetry
        case .foregroundInterrupted:
            return .invalidated
        default:
            return .unavailable
        }
    }

    private static func title(for scenario: Scenario) -> String {
        switch scenario {
        case .stationaryPreflight: return "Confirm setup"
        case .firstPoweredOff: return "Scooter off — first window"
        case .firstPoweredOn: return "Scooter on — first window"
        case .secondPoweredOff: return "Scooter off — second window"
        case .secondPoweredOn: return "Scooter signal found"
        case .targetConfirmation: return "Confirm scooter signal"
        case .passiveDiscovery: return "Reading passive Bluetooth evidence"
        case .observationReady: return "Observation ready"
        case .horizonSealed: return "Capture sealed"
        case .captureComplete: return "Capture complete"
        case .shareRetry: return "Share capture again"
        case .foregroundInterrupted: return "Capture interrupted"
        }
    }

    private static func accessibilitySummary(for scenario: Scenario) -> String {
        "\(evidenceLabel). \(title(for: scenario)). Physical procedure remains locked."
    }
}
#endif
