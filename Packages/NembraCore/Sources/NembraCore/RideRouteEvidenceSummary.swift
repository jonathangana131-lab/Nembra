public enum RideRouteEvidenceShape: String, Equatable, Sendable {
    case noRecordedGeometry
    case recordedPointsOnly
    case drawablePath
}

public enum RideRouteEvidenceSummaryError: Error, Equatable, Sendable {
    case invalidCounts
    case inconsistentEvidence
    case countOverflow
}

/// Truth-preserving summary of persisted route topology for product/UI consumers.
///
/// This type does not infer distance, route legality, place names, or continuity
/// beyond the explicit coverage/topology evidence supplied by the caller.
public struct RideRouteEvidenceSummary: Equatable, Sendable {
    public let coverage: RideDistanceCoverage
    public let segmentCount: Int
    public let pointCount: Int
    public let knownGapCount: Int
    public let shape: RideRouteEvidenceShape

    public init(
        coverage: RideDistanceCoverage,
        segmentPointCounts: [Int],
        knownGapCount: Int
    ) throws {
        guard knownGapCount >= 0,
              segmentPointCounts.allSatisfy({ $0 > 0 }) else {
            throw RideRouteEvidenceSummaryError.invalidCounts
        }

        var pointCount = 0
        for count in segmentPointCounts {
            let (sum, overflow) = pointCount.addingReportingOverflow(count)
            guard !overflow else {
                throw RideRouteEvidenceSummaryError.countOverflow
            }
            pointCount = sum
        }

        let segmentCount = segmentPointCounts.count
        if segmentCount == 0 {
            guard coverage == .unknown, knownGapCount == 0 else {
                throw RideRouteEvidenceSummaryError.inconsistentEvidence
            }
            self.coverage = coverage
            self.segmentCount = 0
            self.pointCount = 0
            self.knownGapCount = 0
            self.shape = .noRecordedGeometry
            return
        }

        guard knownGapCount <= segmentCount - 1 else {
            throw RideRouteEvidenceSummaryError.inconsistentEvidence
        }
        if coverage == .complete, knownGapCount > 0 {
            throw RideRouteEvidenceSummaryError.inconsistentEvidence
        }
        if knownGapCount > 0, coverage != .partial {
            throw RideRouteEvidenceSummaryError.inconsistentEvidence
        }

        self.coverage = coverage
        self.segmentCount = segmentCount
        self.pointCount = pointCount
        self.knownGapCount = knownGapCount
        self.shape = segmentPointCounts.contains(where: { $0 >= 2 })
            ? .drawablePath
            : .recordedPointsOnly
    }

    public var hasRecordedGeometry: Bool {
        shape != .noRecordedGeometry
    }

    public var hasDrawablePath: Bool {
        shape == .drawablePath
    }

    public var hasKnownGaps: Bool {
        knownGapCount > 0
    }
}
