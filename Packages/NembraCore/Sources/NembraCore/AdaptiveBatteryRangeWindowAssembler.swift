import Foundation

public enum BatteryRangeWindowAssemblyError: Error, Equatable, Sendable {
    case invalidDistanceDelta
    case distanceOverflow
    case nonMonotonicAuthoritativeSOC
}

/// Stateful evidence assembler that turns authoritative SoC anchors plus
/// caller-supplied real-distance evidence into `BatteryRangeLearningWindow`
/// candidates.
///
/// This type deliberately does not choose a distance source, decode battery
/// telemetry, infer transport continuity, or train the adaptive model itself.
/// Higher layers must classify those facts truthfully before recording them.
/// Estimated/display SoC is ignored as learning evidence.
public struct BatteryRangeLearningWindowAssembler: Equatable, Sendable {
    public private(set) var anchorSOC: BatterySOCReading?
    public private(set) var accumulatedDistanceMeters: Double
    public private(set) var distanceCoverage: BatteryRangeDistanceCoverage
    public private(set) var transportGapOccurred: Bool

    public init() {
        anchorSOC = nil
        accumulatedDistanceMeters = 0
        distanceCoverage = .complete
        transportGapOccurred = false
    }

    public var hasAuthoritativeAnchor: Bool {
        anchorSOC != nil
    }

    /// Records a nonnegative distance delta that a higher layer has already
    /// classified for coverage. A zero delta is valid and can still be useful
    /// for degrading coverage without inventing distance.
    public mutating func recordDistance(
        deltaMeters: Double,
        coverage: BatteryRangeDistanceCoverage = .complete
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

    /// Marks a scooter-transport continuity break inside the current evidence
    /// span. This is sticky until the span is rebased or reset.
    public mutating func recordTransportGap() {
        transportGapOccurred = true
    }

    /// Ingests a normalized SoC reading and emits a learning-window candidate
    /// only after the active adaptive-range policy's minimum consumption and
    /// distance thresholds are both satisfied.
    ///
    /// - Estimated SoC never establishes or advances a learning anchor.
    /// - Flat authoritative SoC keeps the existing anchor so distance can
    ///   accumulate across coarse/slow percentage updates.
    /// - A higher authoritative SoC conservatively rebases the span. That can
    ///   represent charging, sag recovery, or another non-consumption change;
    ///   none of the preceding distance is relabeled as battery consumption.
    /// - A completed candidate preserves partial/unknown distance coverage and
    ///   transport-gap evidence for `AdaptiveBatteryRangeModel` to reject.
    public mutating func ingestSOC(
        _ reading: BatterySOCReading,
        policy: AdaptiveBatteryRangePolicy
    ) throws -> BatteryRangeLearningWindow? {
        guard reading.isAuthoritativeMeasurement else {
            return nil
        }

        guard let anchorSOC else {
            rebase(to: reading)
            return nil
        }

        guard reading.receivedAtUptimeNanoseconds > anchorSOC.receivedAtUptimeNanoseconds else {
            throw BatteryRangeWindowAssemblyError.nonMonotonicAuthoritativeSOC
        }

        if reading.percentage > anchorSOC.percentage {
            rebase(to: reading)
            return nil
        }

        let consumedPercentagePoints = anchorSOC.percentage - reading.percentage
        guard consumedPercentagePoints >= policy.minimumConsumedPercentagePoints,
              accumulatedDistanceMeters >= policy.minimumDistanceMeters else {
            return nil
        }

        let window = try BatteryRangeLearningWindow(
            distanceMeters: accumulatedDistanceMeters,
            distanceCoverage: distanceCoverage,
            transportGapOccurred: transportGapOccurred,
            startSOC: anchorSOC,
            endSOC: reading
        )

        rebase(to: reading)
        return window
    }

    /// Clears all in-flight evidence at an explicit ride/device/session
    /// boundary. Learned model history belongs to `AdaptiveBatteryRangeModel`
    /// and is intentionally not owned by this ephemeral assembler.
    public mutating func reset() {
        anchorSOC = nil
        resetSpanEvidence()
    }

    private mutating func rebase(to reading: BatterySOCReading) {
        anchorSOC = reading
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
