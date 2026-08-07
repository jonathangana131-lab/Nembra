import Foundation

public enum RideRouteEvidenceShape: String, Equatable, Sendable {
    case noRecordedGeometry
    case recordedPointsOnly
    case drawablePath
}

/// Truth-preserving presentation summary of already-validated route geometry.
///
/// `RideRouteGeometry` remains the authority for persisted topology, session
/// identity, and coverage invariants. This type only projects those accepted
/// facts into a compact shape for UI/accessibility consumers; it does not
/// revalidate, reinterpret, or strengthen the underlying route evidence.
public struct RideRouteEvidenceSummary: Equatable, Sendable {
    /// Preserves the identity already validated by `RideRouteGeometry` so a
    /// presentation consumer does not lose which ride owns this route summary.
    /// This is evidence carried forward from geometry, not a new claim that UUID
    /// equality alone proves lifecycle ownership.
    public let sessionID: UUID
    public let coverage: RideDistanceCoverage
    public let segmentCount: Int
    public let pointCount: Int
    public let knownGapCount: Int
    public let shape: RideRouteEvidenceShape

    public init(geometry: RideRouteGeometry) {
        sessionID = geometry.sessionID
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
