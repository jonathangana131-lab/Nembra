public enum RideRouteEvidenceShape: String, Equatable, Sendable {
    case noRecordedGeometry
    case recordedPointsOnly
    case drawablePath
}

/// Truth-preserving presentation summary of already-validated route geometry.
///
/// `RideRouteGeometry` remains the authority for persisted topology and coverage
/// invariants. This type only projects those accepted facts into a compact shape
/// for UI/accessibility consumers; it does not revalidate, reinterpret, or
/// strengthen the underlying route evidence.
public struct RideRouteEvidenceSummary: Equatable, Sendable {
    public let coverage: RideDistanceCoverage
    public let segmentCount: Int
    public let pointCount: Int
    public let knownGapCount: Int
    public let shape: RideRouteEvidenceShape

    public init(geometry: RideRouteGeometry) {
        coverage = geometry.coverage
        segmentCount = geometry.segments.count
        pointCount = geometry.pointCount
        knownGapCount = geometry.knownGapCount

        if !geometry.hasRecordedGeometry {
            shape = .noRecordedGeometry
        } else if geometry.hasDrawablePath {
            shape = .drawablePath
        } else {
            shape = .recordedPointsOnly
        }
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
