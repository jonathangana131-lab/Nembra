import Foundation
import Testing
@testable import NembraCore

@Suite("Ride route evidence summary")
struct RideRouteEvidenceSummaryTests {
    private let sessionID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    private func geometry(
        coverage: RideDistanceCoverage,
        segmentPointCounts: [Int]
    ) throws -> RideRouteGeometry {
        var chunks: [RideRouteChunk] = []
        var nextSequence: UInt64 = 0

        for (segmentOffset, pointCount) in segmentPointCounts.enumerated() {
            var points: [RideRoutePoint] = []
            for pointOffset in 0..<pointCount {
                points.append(
                    try RideRoutePoint(
                        sequence: nextSequence,
                        latitude: 45.63 + Double(segmentOffset) * 0.001 + Double(pointOffset) * 0.0001,
                        longitude: -122.66 - Double(segmentOffset) * 0.001 - Double(pointOffset) * 0.0001,
                        capturedAtDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(nextSequence))
                    )
                )
                nextSequence += 1
            }

            if !points.isEmpty {
                chunks.append(
                    try RideRouteChunk(
                        id: RideRouteChunkID(
                            sessionID: sessionID,
                            segmentIndex: UInt32(segmentOffset),
                            chunkIndex: 0
                        ),
                        points: points
                    )
                )
            }
        }

        let pointCount = segmentPointCounts.reduce(0, +)
        let segmentCount = segmentPointCounts.count
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: coverage,
            segmentCount: segmentCount,
            pointCount: pointCount,
            knownGapCount: max(0, segmentCount - 1)
        )
        return try RideRouteGeometry(manifest: manifest, chunks: chunks)
    }

    @Test("empty validated geometry stays explicitly unknown")
    func noGeometry() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .unknown, segmentPointCounts: [])
        )
        #expect(summary.coverage == .unknown)
        #expect(summary.shape == .noRecordedGeometry)
        #expect(summary.segmentCount == 0)
        #expect(summary.pointCount == 0)
        #expect(!summary.hasRecordedGeometry)
        #expect(!summary.hasDrawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("one recorded point stays points-only instead of inventing an edge")
    func pointsOnly() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .partial, segmentPointCounts: [1])
        )
        #expect(summary.shape == .recordedPointsOnly)
        #expect(summary.segmentCount == 1)
        #expect(summary.pointCount == 1)
        #expect(summary.hasRecordedGeometry)
        #expect(!summary.hasDrawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("a continuous validated segment with two or more points is drawable")
    func drawablePath() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .complete, segmentPointCounts: [4])
        )
        #expect(summary.coverage == .complete)
        #expect(summary.shape == .drawablePath)
        #expect(summary.segmentCount == 1)
        #expect(summary.pointCount == 4)
        #expect(summary.hasDrawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("partial multi-segment geometry preserves exact known gaps and counts")
    func partialWithKnownGaps() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .partial, segmentPointCounts: [1, 3, 2])
        )
        #expect(summary.coverage == .partial)
        #expect(summary.shape == .drawablePath)
        #expect(summary.segmentCount == 3)
        #expect(summary.pointCount == 6)
        #expect(summary.knownGapCount == 2)
        #expect(summary.hasKnownGaps)
    }

    @Test("unknown coverage with explicit geometry gaps stays unknown")
    func unknownCoverageWithKnownGap() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .unknown, segmentPointCounts: [2, 2])
        )
        #expect(summary.coverage == .unknown)
        #expect(summary.shape == .drawablePath)
        #expect(summary.segmentCount == 2)
        #expect(summary.pointCount == 4)
        #expect(summary.knownGapCount == 1)
        #expect(summary.hasKnownGaps)
    }

    @Test("partial coverage without an interior gap remains partial")
    func partialWithoutInteriorGap() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .partial, segmentPointCounts: [3])
        )
        #expect(summary.coverage == .partial)
        #expect(summary.shape == .drawablePath)
        #expect(!summary.hasKnownGaps)
    }

    @Test("multiple single-point segments remain points-only while preserving gaps")
    func separatedPointsStayPointsOnly() throws {
        let summary = RideRouteEvidenceSummary(
            geometry: try geometry(coverage: .unknown, segmentPointCounts: [1, 1])
        )
        #expect(summary.shape == .recordedPointsOnly)
        #expect(summary.segmentCount == 2)
        #expect(summary.pointCount == 2)
        #expect(summary.knownGapCount == 1)
        #expect(!summary.hasDrawablePath)
        #expect(summary.hasKnownGaps)
    }
}
