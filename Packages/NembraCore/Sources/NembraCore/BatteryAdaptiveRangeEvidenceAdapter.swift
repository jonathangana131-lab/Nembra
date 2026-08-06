/// One truth-preserving action produced when normalized battery evidence is
/// considered for the adaptive percentage-based range domain.
///
/// The adapter is intentionally action-oriented so a caller cannot accidentally
/// discard a known continuity break merely because the first resumed battery
/// field is non-SoC or carries a non-authoritative truth role.
public enum BatteryAdaptiveRangeEvidenceAction: Equatable, Sendable {
    /// This continuous observation must not affect production adaptive-range learning.
    case ignore

    /// Battery evidence resumed after an interval Nembra did not observe. Any
    /// in-flight range-learning anchor/window must be discarded before later
    /// authoritative SoC evidence is accepted.
    case resetContinuity

    /// A continuous, physically verified vehicle SoC reading that is eligible
    /// to enter the adaptive-range domain. Model/window policy still decides
    /// whether it can actually teach efficiency.
    case ingestSOC(BatterySOCReading)

    /// The first verified vehicle SoC after an unobserved interval. The caller
    /// must reset in-flight continuity first, then ingest this reading as the
    /// new clean anchor/evidence point.
    case resetContinuityAndIngestSOC(BatterySOCReading)
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
            // A stock-app/simulation/estimate/presentation value still cannot
            // train range. However, if the evidence stream explicitly says an
            // interval was unobserved, that known gap must close any in-flight
            // learning span so later verified SoC cannot bridge across it.
            return requiresReset ? .resetContinuity : .ignore
        }

        guard observation.value.field == .stateOfChargePercent else {
            // Verified voltage/current/power/charging evidence does not teach
            // percentage-based efficiency, but an explicit first-post-gap
            // marker still resets the range-learning continuity boundary.
            return requiresReset ? .resetContinuity : .ignore
        }

        guard let percentage = observation.value.numericValue else {
            // BatterySemanticValue normally makes this state impossible, and its
            // Codable path revalidates the same invariant. Keep the bridge
            // fail-closed if that upstream contract ever changes.
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
///
/// Keeping this internal prevents external production code from accepting an
/// action without also applying it atomically to the learning-window assembler.
/// Tests use `@testable` to exercise this layer directly.
struct BatteryAdaptiveRangeEvidenceBridge: Equatable, Sendable {
    private(set) var streamValidator: BatteryEvidenceStreamValidator

    init(streamValidator: BatteryEvidenceStreamValidator = .init()) {
        self.streamValidator = streamValidator
    }

    /// Records that evidence was missed before the next observation arrives.
    /// The next observation must carry `.afterUnobservedInterval` or stream
    /// validation fails closed.
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
/// adaptive-range learning window state.
public struct BatteryAdaptiveRangePipelineResult: Equatable, Sendable {
    public let action: BatteryAdaptiveRangeEvidenceAction
    public let learningWindow: BatteryRangeLearningWindow?

    /// Constructed only by the validated pipeline. External code may inspect a
    /// result but cannot manufacture one that appears to have passed the seam.
    init(
        action: BatteryAdaptiveRangeEvidenceAction,
        learningWindow: BatteryRangeLearningWindow?
    ) {
        self.action = action
        self.learningWindow = learningWindow
    }
}

/// End-to-end ephemeral pipeline from normalized battery evidence to candidate
/// adaptive-range learning windows.
///
/// This type still does not select a distance source, classify route coverage,
/// decode BLE/Tuya, or train/persist `AdaptiveBatteryRangeModel`. It keeps the
/// evidence-stream truth boundary and the in-flight window assembler in one
/// atomic state transition so known gaps cannot leak across the seam.
public struct BatteryAdaptiveRangeLearningPipeline: Equatable, Sendable {
    /// Internal on purpose: external production consumers must not mutate or
    /// independently advance the stream validator outside this atomic pipeline.
    private(set) var evidenceBridge: BatteryAdaptiveRangeEvidenceBridge

    /// Read-only externally for diagnostics/UI research. Mutations remain
    /// constrained to the pipeline methods below.
    public private(set) var windowAssembler: BatteryRangeLearningWindowAssembler

    public init() {
        evidenceBridge = BatteryAdaptiveRangeEvidenceBridge()
        windowAssembler = BatteryRangeLearningWindowAssembler()
    }

    /// A higher layer has proof that normalized battery evidence was missed.
    /// Discard the in-flight consumption span immediately and require the next
    /// observation to carry an explicit continuity boundary.
    public mutating func markUnobservedInterval() {
        evidenceBridge.markUnobservedInterval()
        windowAssembler.reset()
    }

    /// Records caller-classified real-distance evidence. The pipeline does not
    /// choose ODO versus GPS and does not upgrade partial/unknown coverage.
    public mutating func recordDistance(
        deltaMeters: Double,
        coverage: BatteryRangeDistanceCoverage = .complete
    ) throws {
        try windowAssembler.recordDistance(
            deltaMeters: deltaMeters,
            coverage: coverage
        )
    }

    /// Records an observed scooter transport gap inside the current learning
    /// span. This is distinct from `markUnobservedInterval()`: an observed gap
    /// remains attached to the candidate so the adaptive model can reject it,
    /// while a genuinely unobserved evidence interval discards the span.
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
