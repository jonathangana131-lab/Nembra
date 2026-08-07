import Testing
@testable import NembraCore

@Suite("Ride distance final-source coverage truth")
struct RideDistanceFinalCoverageTruthTests {
    private func policy() throws -> RideDistanceReconciliationPolicy {
        try RideDistanceReconciliationPolicy(
            sourcePriority: [.gpsRoute, .scooterOdometer, .liveSpeedIntegration],
            absoluteAgreementToleranceMeters: 50,
            relativeAgreementTolerance: 0.03,
            minimumRelativeComparisonDistanceMeters: 100,
            allowOdometerToRecoverKnownCoverageGaps: true
        )
    }

    private func evidence(
        gpsCoverage: RideDistanceCoverage,
        odometerCoverage: RideDistanceCoverage = .complete
    ) throws -> RideDistanceEvidence {
        try RideDistanceEvidence(
            startingOdometerKilometers: 100,
            endingOdometerKilometers: 104.6,
            odometerCoverage: odometerCoverage,
            gpsRouteDistanceMeters: 4_570,
            gpsRouteCoverage: gpsCoverage,
            liveIntegratedDistanceMeters: nil,
            liveIntegratedCoverage: .unknown,
            transportGapOccurred: gpsCoverage == .partial || odometerCoverage == .partial
        )
    }

    @Test("complete corroboration cannot upgrade a selected partial source")
    func partialSelectedSourceRemainsIncomplete() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gpsCoverage: .partial),
            policy: try policy()
        )

        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 4_570)
        #expect(result.finalSourceCoverage == .partial)
        #expect(result.confidence == .corroborated)
        #expect(result.status == .coverageIncomplete)
        #expect(result.comparisons.count == 1)
        #expect(result.comparisons.first?.source == .scooterOdometer)
        #expect(result.comparisons.first?.coverage == .complete)
        #expect(result.comparisons.first?.disposition == .agrees)
    }

    @Test("complete corroboration cannot upgrade selected unknown coverage")
    func unknownSelectedSourceRemainsIncomplete() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gpsCoverage: .unknown),
            policy: try policy()
        )

        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 4_570)
        #expect(result.finalSourceCoverage == .unknown)
        #expect(result.confidence == .corroborated)
        #expect(result.status == .coverageIncomplete)
        #expect(result.comparisons.first?.coverage == .complete)
        #expect(result.comparisons.first?.disposition == .agrees)
    }

    @Test("partial corroboration cannot downgrade a selected complete source")
    func completeSelectedSourceRemainsComplete() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gpsCoverage: .complete, odometerCoverage: .partial),
            policy: try policy()
        )

        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 4_570)
        #expect(result.finalSourceCoverage == .complete)
        #expect(result.confidence == .corroborated)
        #expect(result.status == .complete)
        #expect(result.comparisons.first?.coverage == .partial)
        #expect(result.comparisons.first?.disposition == .agrees)
    }
}
