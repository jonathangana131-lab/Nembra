import Foundation
import Testing
@testable import NembraCore

@Suite("Ride route evidence summary session identity")
struct RideRouteEvidenceSummarySessionIdentityTests {
    private func emptyGeometry(sessionID: UUID) throws -> RideRouteGeometry {
        let manifest = try RideRouteManifest(
            sessionID: sessionID,
            coverage: .unknown,
            segmentCount: 0,
            pointCount: 0,
            knownGapCount: 0
        )
        return try RideRouteGeometry(manifest: manifest, chunks: [])
    }

    @Test("summary preserves the geometry session identity")
    func preservesSessionIdentity() throws {
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let summary = RideRouteEvidenceSummary(
            geometry: try emptyGeometry(sessionID: sessionID)
        )

        #expect(summary.sessionID == sessionID)
        #expect(summary.shape == .noRecordedGeometry)
        #expect(summary.coverage == .unknown)
    }

    @Test("otherwise identical route summaries remain distinct across rides")
    func identicalRouteFactsRemainRideDistinct() throws {
        let firstSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let secondSessionID = UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!

        let first = RideRouteEvidenceSummary(
            geometry: try emptyGeometry(sessionID: firstSessionID)
        )
        let second = RideRouteEvidenceSummary(
            geometry: try emptyGeometry(sessionID: secondSessionID)
        )

        #expect(first.sessionID != second.sessionID)
        #expect(first != second)
        #expect(first.coverage == second.coverage)
        #expect(first.segmentCount == second.segmentCount)
        #expect(first.pointCount == second.pointCount)
        #expect(first.knownGapCount == second.knownGapCount)
        #expect(first.shape == second.shape)
    }
}
