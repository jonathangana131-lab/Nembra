import Testing
@testable import NembraCore

@Suite("Ride route evidence summary")
struct RideRouteEvidenceSummaryTests {
    @Test("no geometry remains explicitly unknown")
    func noGeometry() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .unknown,
            segmentPointCounts: [],
            knownGapCount: 0
        )
        #expect(summary.shape == .noRecordedGeometry)
        #expect(summary.segmentCount == 0)
        #expect(summary.pointCount == 0)
        #expect(!summary.hasRecordedGeometry)
        #expect(!summary.hasDrawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("single points remain points-only instead of inventing a path")
    func pointsOnly() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .partial,
            segmentPointCounts: [1, 1],
            knownGapCount: 1
        )
        #expect(summary.shape == .recordedPointsOnly)
        #expect(summary.segmentCount == 2)
        #expect(summary.pointCount == 2)
        #expect(summary.hasRecordedGeometry)
        #expect(!summary.hasDrawablePath)
        #expect(summary.hasKnownGaps)
    }

    @Test("any continuous segment with two points can draw only that recorded path")
    func drawablePath() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .partial,
            segmentPointCounts: [1, 3, 1],
            knownGapCount: 2
        )
        #expect(summary.shape == .drawablePath)
        #expect(summary.segmentCount == 3)
        #expect(summary.pointCount == 5)
        #expect(summary.hasDrawablePath)
        #expect(summary.hasKnownGaps)
    }

    @Test("complete recorded coverage can expose a drawable path without gaps")
    func completePath() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .complete,
            segmentPointCounts: [4],
            knownGapCount: 0
        )
        #expect(summary.coverage == .complete)
        #expect(summary.shape == .drawablePath)
        #expect(summary.segmentCount == 1)
        #expect(summary.pointCount == 4)
        #expect(!summary.hasKnownGaps)
    }

    @Test("complete coverage cannot coexist with known route gaps")
    func completeWithGapRejected() {
        #expect(throws: RideRouteEvidenceSummaryError.inconsistentEvidence) {
            _ = try RideRouteEvidenceSummary(
                coverage: .complete,
                segmentPointCounts: [2, 2],
                knownGapCount: 1
            )
        }
    }

    @Test("known gaps require partial coverage")
    func gapsRequirePartialCoverage() {
        #expect(throws: RideRouteEvidenceSummaryError.inconsistentEvidence) {
            _ = try RideRouteEvidenceSummary(
                coverage: .unknown,
                segmentPointCounts: [2, 2],
                knownGapCount: 1
            )
        }
    }

    @Test("partial coverage can exist without a materialized interior gap")
    func partialWithoutInteriorGap() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .partial,
            segmentPointCounts: [3],
            knownGapCount: 0
        )
        #expect(summary.shape == .drawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("unknown coverage can preserve recorded geometry without claiming completeness")
    func unknownCoverageWithGeometry() throws {
        let summary = try RideRouteEvidenceSummary(
            coverage: .unknown,
            segmentPointCounts: [4],
            knownGapCount: 0
        )
        #expect(summary.shape == .drawablePath)
        #expect(summary.coverage == .unknown)
    }

    @Test("point-count overflow fails closed")
    func pointCountOverflowRejected() {
        #expect(throws: RideRouteEvidenceSummaryError.countOverflow) {
            _ = try RideRouteEvidenceSummary(
                coverage: .partial,
                segmentPointCounts: [Int.max, 1],
                knownGapCount: 1
            )
        }
    }

    @Test("empty or impossible topology is rejected")
    func invalidTopologyRejected() {
        #expect(throws: RideRouteEvidenceSummaryError.invalidCounts) {
            _ = try RideRouteEvidenceSummary(
                coverage: .unknown,
                segmentPointCounts: [0],
                knownGapCount: 0
            )
        }
        #expect(throws: RideRouteEvidenceSummaryError.invalidCounts) {
            _ = try RideRouteEvidenceSummary(
                coverage: .partial,
                segmentPointCounts: [2],
                knownGapCount: -1
            )
        }
        #expect(throws: RideRouteEvidenceSummaryError.inconsistentEvidence) {
            _ = try RideRouteEvidenceSummary(
                coverage: .partial,
                segmentPointCounts: [2],
                knownGapCount: 1
            )
        }
        #expect(throws: RideRouteEvidenceSummaryError.inconsistentEvidence) {
            _ = try RideRouteEvidenceSummary(
                coverage: .partial,
                segmentPointCounts: [],
                knownGapCount: 0
            )
        }
    }
}
