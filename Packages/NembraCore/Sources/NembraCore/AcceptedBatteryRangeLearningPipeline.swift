#if SWIFT_PACKAGE
/// Public, payload-safe result of admitting one battery observation into the
/// accepted learned-range evidence pipeline.
///
/// `acceptedSOC` exists only when the sealed battery evidence stream accepted a
/// verified vehicle SoC receipt. `candidateLearningWindow` is still only an
/// evidence candidate; it has not been accepted into learned history.
public struct AcceptedBatteryRangePipelineResult: Equatable, Sendable {
    public let acceptedSOC: AcceptedBatterySOCAnchor?
    public let candidateLearningWindow: AcceptedBatteryRangeLearningWindow?

    fileprivate init(
        acceptedSOC: AcceptedBatterySOCAnchor?,
        candidateLearningWindow: AcceptedBatteryRangeLearningWindow?
    ) {
        self.acceptedSOC = acceptedSOC
        self.candidateLearningWindow = candidateLearningWindow
    }
}

/// Production-facing package bridge from accepted battery receipt chronology to
/// receipt/continuity-bound learned-range window candidates.
///
/// This bridge deliberately does not decode ES80 bytes, choose a distance source,
/// invent distance coverage, persist learned history, or treat candidate emission
/// as model acceptance. All normalized battery callbacks that belong to one live
/// acquisition chronology should pass through `acceptBatteryObservation` so the
/// wrapped `AcceptedBatterySOCStream` sees every receipt and continuity boundary.
///
/// Battery receipt chronology is stronger than downstream range assembly. If the
/// battery stream consumes a callback and later range-window assembly cannot use
/// it, the accepted/seen battery chronology is intentionally not rolled back. A
/// downstream failure must never reopen an older receipt for acceptance.
///
/// Currentness authority intentionally stays inside this owner. A copyable
/// `BatteryEvidenceStreamValidator` snapshot is not exported: an old snapshot can
/// remain internally consistent with R1 after the real owner has crossed a gap or
/// accepted R2, so exposing it would let retained R1 be replayed as current.
/// Downstream live presentation must wait for a non-replayable owner-bound
/// projection rather than caching validator values.
public struct AcceptedBatteryRangeLearningPipeline: Sendable {
    private var socStream: AcceptedBatterySOCStream
    private var windowState: AcceptedBatteryRangeWindowState

    public init() {
        socStream = AcceptedBatterySOCStream()
        windowState = AcceptedBatteryRangeWindowState()
    }

    /// A higher layer has proof that battery observation continuity was lost.
    /// The battery stream keeps its receipt watermark and requires a strictly
    /// newer explicit boundary. In-flight learned-range evidence is discarded.
    public mutating func markUnobservedInterval() {
        socStream.markUnobservedInterval()
        windowState.reset()
    }

    /// Records a nonnegative real-distance delta already classified by a higher
    /// authority. Omitted coverage fails closed as `.unknown`.
    public mutating func recordDistance(
        deltaMeters: Double,
        coverage: BatteryRangeDistanceCoverage = .unknown
    ) throws {
        try windowState.recordDistance(
            deltaMeters: deltaMeters,
            coverage: coverage
        )
    }

    /// Marks a range-learning span as having a transport gap. This is separate
    /// from `markUnobservedInterval()`: callers should use the latter whenever
    /// the battery evidence stream itself was unobserved.
    public mutating func recordTransportGap() {
        windowState.recordTransportGap()
    }

    /// Admits one normalized battery observation and, for verified SoC only,
    /// advances the accepted range-learning span.
    ///
    /// Stream admission happens on the real stream first. This is intentional:
    /// `BatteryEvidenceStreamValidator` may consume a newer receipt watermark even
    /// when that callback is rejected later, and downstream range errors must not
    /// undo that chronology. Range-window state is committed only after its own
    /// transition succeeds.
    public mutating func acceptBatteryObservation(
        _ observation: BatteryEvidenceObservation,
        policy: AdaptiveBatteryRangePolicy
    ) throws -> AcceptedBatteryRangePipelineResult {
        let acceptedSOC = try socStream.accept(observation)

        // A boundary may arrive on a non-SoC sibling before the SoC field from the
        // same receipt. Rotate the ephemeral learning span as soon as the accepted
        // stream proves that the continuity segment changed.
        if let anchorSegment = windowState.anchorSOC?.continuitySegmentStartReceiptIdentity,
           let currentSegment = socStream.continuitySegmentStartReceiptIdentity,
           anchorSegment != currentSegment {
            windowState.reset()
        }

        var candidateState = windowState
        let candidateWindow: AcceptedBatteryRangeLearningWindow?
        if let acceptedSOC {
            candidateWindow = try candidateState.ingestSOC(
                acceptedSOC,
                policy: policy
            )
        } else {
            candidateWindow = nil
        }

        windowState = candidateState
        return AcceptedBatteryRangePipelineResult(
            acceptedSOC: acceptedSOC,
            candidateLearningWindow: candidateWindow
        )
    }

    /// Internal-only equivalence for adversarial atomicity tests. No public
    /// equality over hidden evidence state is exposed as a telemetry side channel.
    func hasSameInternalRangeState(
        as other: AcceptedBatteryRangeLearningPipeline
    ) -> Bool {
        windowState == other.windowState
    }
}

private struct AcceptedBatteryRangeWindowState: Equatable, Sendable {
    var anchorSOC: AcceptedBatterySOCAnchor?
    var latestAcceptedSOC: AcceptedBatterySOCAnchor?
    var accumulatedDistanceMeters: Double
    var distanceCoverage: BatteryRangeDistanceCoverage
    var transportGapOccurred: Bool

    init() {
        anchorSOC = nil
        latestAcceptedSOC = nil
        accumulatedDistanceMeters = 0
        distanceCoverage = .complete
        transportGapOccurred = false
    }

    mutating func recordDistance(
        deltaMeters: Double,
        coverage: BatteryRangeDistanceCoverage
    ) throws {
        guard deltaMeters.isFinite, deltaMeters >= 0 else {
            throw BatteryRangeWindowAssemblyError.invalidDistanceDelta
        }

        let candidateDistance = accumulatedDistanceMeters + deltaMeters
        guard candidateDistance.isFinite else {
            throw BatteryRangeWindowAssemblyError.distanceOverflow
        }

        accumulatedDistanceMeters = candidateDistance
        distanceCoverage = Self.mergedCoverage(distanceCoverage, coverage)
    }

    mutating func recordTransportGap() {
        transportGapOccurred = true
    }

    mutating func ingestSOC(
        _ reading: AcceptedBatterySOCAnchor,
        policy: AdaptiveBatteryRangePolicy
    ) throws -> AcceptedBatteryRangeLearningWindow? {
        guard let anchorSOC else {
            rebase(to: reading)
            return nil
        }

        let latest = latestAcceptedSOC ?? anchorSOC
        guard reading.sourceReceiptIdentity.acquisitionEpoch
                == latest.sourceReceiptIdentity.acquisitionEpoch,
              reading.sourceReceiptIdentity.sequenceNumber
                > latest.sourceReceiptIdentity.sequenceNumber else {
            throw AcceptedAdaptiveRangeValidationError.invalidReceiptOrder
        }

        if reading.percentage > latest.percentage {
            rebase(to: reading)
            return nil
        }

        let consumedPercentagePoints = anchorSOC.percentage - reading.percentage
        guard consumedPercentagePoints >= policy.minimumConsumedPercentagePoints,
              accumulatedDistanceMeters >= policy.minimumDistanceMeters else {
            latestAcceptedSOC = reading
            return nil
        }

        // Distinct accepted receipts may legitimately share one monotonic uptime
        // tick. Receipt sequence remains authoritative chronology, but a learning
        // window whose endpoints have no positive observed uptime span is deferred
        // rather than promoted into the stricter accepted-window type.
        guard reading.receivedAtUptimeNanoseconds
                > anchorSOC.receivedAtUptimeNanoseconds else {
            latestAcceptedSOC = reading
            return nil
        }

        let window = try AcceptedBatteryRangeLearningWindow(
            distanceMeters: accumulatedDistanceMeters,
            distanceCoverage: distanceCoverage,
            transportGapOccurred: transportGapOccurred,
            startSOC: anchorSOC,
            endSOC: reading
        )

        rebase(to: reading)
        return window
    }

    mutating func reset() {
        anchorSOC = nil
        latestAcceptedSOC = nil
        resetSpanEvidence()
    }

    private mutating func rebase(to reading: AcceptedBatterySOCAnchor) {
        anchorSOC = reading
        latestAcceptedSOC = reading
        resetSpanEvidence()
    }

    private mutating func resetSpanEvidence() {
        accumulatedDistanceMeters = 0
        distanceCoverage = .complete
        transportGapOccurred = false
    }

    private static func mergedCoverage(
        _ lhs: BatteryRangeDistanceCoverage,
        _ rhs: BatteryRangeDistanceCoverage
    ) -> BatteryRangeDistanceCoverage {
        switch (lhs, rhs) {
        case (.unknown, _), (_, .unknown):
            return .unknown
        case (.partial, _), (_, .partial):
            return .partial
        case (.complete, .complete):
            return .complete
        }
    }
}
#endif
