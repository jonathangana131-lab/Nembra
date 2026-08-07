/// One truth-preserving action produced when normalized battery evidence is
/// considered for the adaptive percentage-based range domain.
///
/// This type is intentionally module-internal. It carries an authoritative SoC
/// reading only after the sealed battery-evidence boundary has accepted that
/// observation, so external callers must never be able to manufacture one and
/// present it as pipeline-validated evidence.
enum BatteryAdaptiveRangeEvidenceAction: Equatable, Sendable {
    case ignore
    case resetContinuity
    case ingestSOC(BatterySOCReading)
    case resetContinuityAndIngestSOC(BatterySOCReading)

    var publicDisposition: BatteryAdaptiveRangePipelineDisposition {
        switch self {
        case .ignore:
            return .ignored
        case .resetContinuity:
            return .continuityReset
        case .ingestSOC:
            return .authoritativeSOCIngested
        case .resetContinuityAndIngestSOC:
            return .continuityResetAndAuthoritativeSOCIngested
        }
    }
}

/// Payload-free public classification of what one validated pipeline transition
/// did. This is safe to expose because it cannot carry or manufacture an
/// authoritative SoC reading. "Ingested" means accepted into the ephemeral
/// evidence/window pipeline; it does not imply acceptance into learned history.
public enum BatteryAdaptiveRangePipelineDisposition: Equatable, Sendable {
    case ignored
    case continuityReset
    case authoritativeSOCIngested
    case continuityResetAndAuthoritativeSOCIngested
}

/// Pure semantic helper used by the stateful bridge.
///
/// This intentionally remains internal to NembraCore so external production
/// consumers cannot bypass process-local stream validation by converting an
/// observation directly. The public path is `BatteryAdaptiveRangeLearningPipeline`.
enum BatteryAdaptiveRangeEvidenceAdapter {
    static func action(
        for observation: BatteryEvidenceObservation
    ) throws -> BatteryAdaptiveRangeEvidenceAction {
        let requiresReset = observation.requiresNewContinuityAnchor

        guard observation.isAuthoritativeVehicleMeasurement else {
            return requiresReset ? .resetContinuity : .ignore
        }

        guard observation.value.field == .stateOfChargePercent else {
            return requiresReset ? .resetContinuity : .ignore
        }

        guard let percentage = observation.value.numericValue else {
            throw BatteryEvidenceValidationError.invalidSemanticValue
        }

        let reading = try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: observation.receivedAtUptimeNanoseconds
        )

        return requiresReset
            ? .resetContinuityAndIngestSOC(reading)
            : .ingestSOC(reading)
    }
}

/// Internal stateful seam that enforces the battery evidence stream's ordering
/// contract before returning an adaptive-range action.
struct BatteryAdaptiveRangeEvidenceBridge: Equatable, Sendable {
    private(set) var streamValidator: BatteryEvidenceStreamValidator

    init(streamValidator: BatteryEvidenceStreamValidator = .init()) {
        self.streamValidator = streamValidator
    }

    mutating func markUnobservedInterval() {
        streamValidator.markUnobservedInterval()
    }

    mutating func accept(
        _ observation: BatteryEvidenceObservation
    ) throws -> BatteryAdaptiveRangeEvidenceAction {
        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: observation)

        var candidateValidator = streamValidator
        try candidateValidator.accept(observation)
        streamValidator = candidateValidator

        return action
    }
}

/// Result of applying one validated battery observation to the in-flight
/// adaptive-range learning-window state.
///
/// `candidateLearningWindow` is deliberately named as a candidate: emitting a
/// window does not mean `AdaptiveBatteryRangeModel` has accepted it into learned
/// history. Coverage, transport-gap, outlier, and other model gates still apply.
public struct BatteryAdaptiveRangePipelineResult: Equatable, Sendable {
    /// Internal evidence-bearing action retained for module tests and pipeline
    /// implementation. External callers receive only `disposition`.
    let action: BatteryAdaptiveRangeEvidenceAction

    public let disposition: BatteryAdaptiveRangePipelineDisposition
    public let candidateLearningWindow: BatteryRangeLearningWindow?

    /// Internal compatibility spelling for module tests/implementation. Keeping
    /// this non-public prevents external callers from mistaking an assembler
    /// candidate for model-accepted learned history.
    var learningWindow: BatteryRangeLearningWindow? {
        candidateLearningWindow
    }

    /// Constructed only by the validated pipeline. External code may inspect a
    /// result but cannot manufacture one that appears to have passed the seam.
    init(
        action: BatteryAdaptiveRangeEvidenceAction,
        learningWindow: BatteryRangeLearningWindow?
    ) {
        self.action = action
        self.disposition = action.publicDisposition
        self.candidateLearningWindow = learningWindow
    }
}

/// End-to-end ephemeral pipeline from normalized battery evidence to candidate
/// adaptive-range learning windows.
///
/// This type does not select a distance source, decode BLE/Tuya, train/persist
/// `AdaptiveBatteryRangeModel`, or expose ephemeral assembler state as UI truth.
public struct BatteryAdaptiveRangeLearningPipeline: Equatable, Sendable {
    private(set) var evidenceBridge: BatteryAdaptiveRangeEvidenceBridge

    /// Internal learning machinery, never a public presentation model.
    private(set) var windowAssembler: BatteryRangeLearningWindowAssembler

    public init() {
        evidenceBridge = BatteryAdaptiveRangeEvidenceBridge()
        windowAssembler = BatteryRangeLearningWindowAssembler()
    }

    /// A higher layer has proof that normalized battery evidence was missed.
    public mutating func markUnobservedInterval() {
        evidenceBridge.markUnobservedInterval()
        windowAssembler.reset()
    }

    /// Records caller-classified real-distance evidence.
    ///
    /// Omitted coverage intentionally means `.unknown`, never `.complete`.
    /// This preserves source compatibility while making an unclassified distance
    /// fail closed at adaptive-model ingest instead of silently training range.
    /// A caller that has proven complete coverage must say so explicitly.
    public mutating func recordDistance(
        deltaMeters: Double,
        coverage: BatteryRangeDistanceCoverage = .unknown
    ) throws {
        try windowAssembler.recordDistance(
            deltaMeters: deltaMeters,
            coverage: coverage
        )
    }

    /// Records an observed scooter transport gap inside the current learning span.
    public mutating func recordTransportGap() {
        windowAssembler.recordTransportGap()
    }

    /// Validates and applies one battery observation atomically across both the
    /// evidence-stream baseline and the learning-window assembler.
    public mutating func acceptBatteryObservation(
        _ observation: BatteryEvidenceObservation,
        policy: AdaptiveBatteryRangePolicy
    ) throws -> BatteryAdaptiveRangePipelineResult {
        var candidateBridge = evidenceBridge
        var candidateAssembler = windowAssembler

        let action = try candidateBridge.accept(observation)
        let window = try Self.apply(
            action,
            policy: policy,
            to: &candidateAssembler
        )

        evidenceBridge = candidateBridge
        windowAssembler = candidateAssembler

        return BatteryAdaptiveRangePipelineResult(
            action: action,
            learningWindow: window
        )
    }

    private static func apply(
        _ action: BatteryAdaptiveRangeEvidenceAction,
        policy: AdaptiveBatteryRangePolicy,
        to assembler: inout BatteryRangeLearningWindowAssembler
    ) throws -> BatteryRangeLearningWindow? {
        switch action {
        case .ignore:
            return nil
        case .resetContinuity:
            assembler.reset()
            return nil
        case let .ingestSOC(reading):
            return try assembler.ingestSOC(reading, policy: policy)
        case let .resetContinuityAndIngestSOC(reading):
            assembler.reset()
            return try assembler.ingestSOC(reading, policy: policy)
        }
    }
}
