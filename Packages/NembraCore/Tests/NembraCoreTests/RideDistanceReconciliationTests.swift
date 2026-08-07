import Foundation
import Testing
@testable import NembraCore

@Suite("Ride distance reconciliation")
struct RideDistanceReconciliationTests {
    private func isNear(_ lhs: Double?, _ rhs: Double, tolerance: Double = 0.000_001) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }

    private func policy(
        priority: [RideDistanceSource] = [.scooterOdometer, .gpsRoute, .liveSpeedIntegration],
        allowGapRecovery: Bool = true
    ) throws -> RideDistanceReconciliationPolicy {
        try RideDistanceReconciliationPolicy(
            sourcePriority: priority,
            absoluteAgreementToleranceMeters: 50,
            relativeAgreementTolerance: 0.03,
            minimumRelativeComparisonDistanceMeters: 100,
            allowOdometerToRecoverKnownCoverageGaps: allowGapRecovery
        )
    }

    private func evidence(
        startODO: Double? = 100,
        endODO: Double? = 104.6,
        odoCoverage: RideDistanceCoverage = .complete,
        gps: Double? = 4_600,
        gpsCoverage: RideDistanceCoverage = .complete,
        live: Double? = 4_600,
        liveCoverage: RideDistanceCoverage = .complete,
        transportGap: Bool = false
    ) throws -> RideDistanceEvidence {
        try RideDistanceEvidence(
            startingOdometerKilometers: startODO,
            endingOdometerKilometers: endODO,
            odometerCoverage: startODO == nil && endODO == nil ? .unknown : odoCoverage,
            gpsRouteDistanceMeters: gps,
            gpsRouteCoverage: gps == nil ? .unknown : gpsCoverage,
            liveIntegratedDistanceMeters: live,
            liveIntegratedCoverage: live == nil ? .unknown : liveCoverage,
            transportGapOccurred: transportGap
        )
    }

    @Test("invalid evidence and policy shapes are rejected")
    func invalidShapesRejected() {
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                startingOdometerKilometers: 10,
                endingOdometerKilometers: nil,
                odometerCoverage: .unknown,
                gpsRouteDistanceMeters: nil,
                gpsRouteCoverage: .unknown,
                liveIntegratedDistanceMeters: nil,
                liveIntegratedCoverage: .unknown,
                transportGapOccurred: false
            )
        }
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try evidence(startODO: 10, endODO: 9)
        }
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try evidence(gps: .infinity)
        }
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                startingOdometerKilometers: nil,
                endingOdometerKilometers: nil,
                odometerCoverage: .complete,
                gpsRouteDistanceMeters: nil,
                gpsRouteCoverage: .unknown,
                liveIntegratedDistanceMeters: nil,
                liveIntegratedCoverage: .unknown,
                transportGapOccurred: false
            )
        }
        #expect(throws: RideDistanceReconciliationError.invalidEvidence) {
            _ = try RideDistanceEvidence(
                startingOdometerKilometers: nil,
                endingOdometerKilometers: nil,
                odometerCoverage: .unknown,
                gpsRouteDistanceMeters: nil,
                gpsRouteCoverage: .complete,
                liveIntegratedDistanceMeters: nil,
                liveIntegratedCoverage: .unknown,
                transportGapOccurred: false
            )
        }
        #expect(throws: RideDistanceReconciliationError.invalidPolicy) {
            _ = try RideDistanceReconciliationPolicy(
                sourcePriority: [.scooterOdometer, .gpsRoute],
                absoluteAgreementToleranceMeters: 1,
                relativeAgreementTolerance: 0.01,
                minimumRelativeComparisonDistanceMeters: 1,
                allowOdometerToRecoverKnownCoverageGaps: true
            )
        }
        #expect(throws: RideDistanceReconciliationError.invalidPolicy) {
            _ = try RideDistanceReconciliationPolicy(
                sourcePriority: [.scooterOdometer, .gpsRoute, .liveSpeedIntegration],
                absoluteAgreementToleranceMeters: 1,
                relativeAgreementTolerance: 1.1,
                minimumRelativeComparisonDistanceMeters: 1,
                allowOdometerToRecoverKnownCoverageGaps: true
            )
        }
    }

    @Test("no evidence stays explicitly unavailable")
    func noEvidenceUnavailable() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(startODO: nil, endODO: nil, gps: nil, live: nil),
            policy: try policy()
        )
        #expect(result.finalDistanceMeters == nil)
        #expect(result.finalSource == nil)
        #expect(result.finalSourceCoverage == nil)
        #expect(result.confidence == .unavailable)
        #expect(result.status == .insufficientEvidence)
    }

    @Test("one complete source remains one source instead of acquiring fake corroboration")
    func singleSourceTruth() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: nil, live: nil),
            policy: try policy()
        )
        #expect(isNear(result.finalDistanceMeters, 4_600))
        #expect(result.finalSource == .scooterOdometer)
        #expect(result.finalSourceCoverage == .complete)
        #expect(result.confidence == .singleSource)
        #expect(result.status == .complete)
        #expect(result.comparisons.isEmpty)
    }

    @Test("one unknown-coverage source remains explicitly incomplete")
    func unknownSingleSourceIsIncomplete() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(odoCoverage: .unknown, gps: nil, live: nil),
            policy: try policy()
        )
        #expect(result.confidence == .singleSource)
        #expect(result.status == .coverageIncomplete)
    }

    @Test("agreeing independent complete sources corroborate the selected distance")
    func corroboratedDistance() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 4_570, live: 4_610),
            policy: try policy()
        )
        #expect(isNear(result.finalDistanceMeters, 4_600))
        #expect(result.confidence == .corroborated)
        #expect(result.status == .complete)
        #expect(result.comparisons.allSatisfy { $0.disposition == .agrees })
    }

    @Test("known GPS coverage gap can recover proven vehicle mileage only from complete ODO")
    func odometerRecoversGPSGap() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 3_000, gpsCoverage: .partial, live: nil, transportGap: true),
            policy: try policy()
        )
        #expect(isNear(result.finalDistanceMeters, 4_600))
        #expect(result.finalSource == .scooterOdometer)
        #expect(result.status == .vehicleDistanceRecoveredAcrossCoverageGap)
        #expect(result.confidence == .recoverySupported)
        #expect(abs(result.recoveredCoverageGapMeters - 1_600) < 0.000_001)
        #expect(result.comparisons.first?.coverage == .partial)
        #expect(result.comparisons.first?.disposition == .explainedCoverageGap)
        #expect(isNear(result.comparisons.first?.recoveredGapMeters, 1_600))
    }

    @Test("partial or unknown ODO can never claim to recover another source gap")
    func incompleteOdometerCannotRecoverGap() throws {
        for coverage in [RideDistanceCoverage.partial, .unknown] {
            let result = RideDistanceReconciler.reconcile(
                evidence: try evidence(
                    odoCoverage: coverage,
                    gps: 3_000,
                    gpsCoverage: .partial,
                    live: nil,
                    transportGap: true
                ),
                policy: try policy()
            )
            #expect(result.status == .disagreementRequiresReview)
            #expect(result.confidence == .conflicting)
            #expect(result.recoveredCoverageGapMeters == 0)
        }
    }

    @Test("unknown secondary coverage is never reclassified as an explained gap")
    func unknownSecondaryCannotBeExplained() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 3_000, gpsCoverage: .unknown, live: nil),
            policy: try policy()
        )
        #expect(result.status == .disagreementRequiresReview)
        #expect(result.comparisons.first?.disposition == .conflicts)
    }

    @Test("missing live telemetry can be explained by complete ODO while complete GPS corroborates")
    func odometerRecoveryWithCorroboration() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(
                gps: 4_590,
                live: 3_500,
                liveCoverage: .partial,
                transportGap: true
            ),
            policy: try policy()
        )
        #expect(result.status == .vehicleDistanceRecoveredAcrossCoverageGap)
        #expect(result.confidence == .corroborated)
        #expect(abs(result.recoveredCoverageGapMeters - 1_100) < 0.000_001)
        #expect(result.comparisons.contains { $0.source == .gpsRoute && $0.disposition == .agrees })
        #expect(result.comparisons.contains { $0.source == .liveSpeedIntegration && $0.disposition == .explainedCoverageGap })
    }

    @Test("large unexplained disagreement is surfaced instead of averaged away")
    func disagreementIsExplicit() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 3_000, live: 4_600),
            policy: try policy()
        )
        #expect(isNear(result.finalDistanceMeters, 4_600))
        #expect(result.confidence == .conflicting)
        #expect(result.status == .disagreementRequiresReview)
        #expect(result.comparisons.contains { $0.source == .gpsRoute && $0.disposition == .conflicts })
    }

    @Test("a partial secondary source that exceeds ODO still conflicts")
    func higherSecondaryStillConflicts() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 5_500, gpsCoverage: .partial, live: nil),
            policy: try policy()
        )
        #expect(result.confidence == .conflicting)
        #expect(result.comparisons.first?.disposition == .conflicts)
        #expect(result.recoveredCoverageGapMeters == 0)
    }

    @Test("gap recovery is policy controlled and can be disabled until vehicle validation supports it")
    func gapRecoveryCanBeDisabled() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 3_000, gpsCoverage: .partial, live: nil),
            policy: try policy(allowGapRecovery: false)
        )
        #expect(result.confidence == .conflicting)
        #expect(result.status == .disagreementRequiresReview)
    }

    @Test("source priority is explicit and no hidden averaging changes the chosen source")
    func explicitSourcePriority() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(gps: 4_000, live: 4_200),
            policy: try policy(priority: [.gpsRoute, .liveSpeedIntegration, .scooterOdometer], allowGapRecovery: false)
        )
        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 4_000)
        #expect(result.finalDistanceMeters != (4_600 + 4_000 + 4_200) / 3)
    }

    @Test("an unrecovered selected source with partial coverage stays explicitly incomplete")
    func selectedCoverageGapIsIncomplete() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(
                startODO: nil,
                endODO: nil,
                gps: 2_345,
                gpsCoverage: .partial,
                live: nil
            ),
            policy: try policy()
        )
        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 2_345)
        #expect(result.confidence == .singleSource)
        #expect(result.status == .coverageIncomplete)
    }

    @Test("GPS is a legitimate complete fallback when scooter ODO was never observed")
    func gpsFallback() throws {
        let result = RideDistanceReconciler.reconcile(
            evidence: try evidence(startODO: nil, endODO: nil, gps: 2_345, live: nil),
            policy: try policy()
        )
        #expect(result.finalSource == .gpsRoute)
        #expect(result.finalDistanceMeters == 2_345)
        #expect(result.finalSourceCoverage == .complete)
        #expect(result.confidence == .singleSource)
        #expect(result.status == .complete)
    }

    @Test("completed ride bridge consumes session-bound live aggregate coverage")
    func completedRideBridge() throws {
        let sessionID = UUID()
        let completed = try CompletedRideEvidence(
            sessionID: sessionID,
            beganAtDate: Date(timeIntervalSince1970: 1_700_000_000),
            confirmedAtDate: Date(timeIntervalSince1970: 1_700_000_001),
            endedAtDate: Date(timeIntervalSince1970: 1_700_000_100),
            startingOdometerKilometers: 143.2,
            endingOdometerKilometers: 147.8,
            qualityScreenedGPSDistanceMeters: 5_000,
            continuity: .recoveredCheckpoint
        )
        let finalized = FinalizedLiveDistanceSegment(
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            segmentStartUptimeNanoseconds: 0,
            segmentEndUptimeNanoseconds: 1,
            firstAcceptedSampleUptimeNanoseconds: 0,
            lastAcceptedSampleUptimeNanoseconds: 1,
            distanceMeters: 5_100,
            coverage: .partial,
            acceptedSampleCount: 2,
            integratedIntervalCount: 1,
            knownCoverageGapCount: 1
        )
        let durable = try RideLiveDistanceSegmentEvidence(
            rideSessionID: sessionID,
            segmentID: UUID(),
            processSegmentSequence: 0,
            finalizedSegment: finalized
        )
        let liveAggregate = try RideLiveDistanceAggregator.aggregate(
            rideSessionID: sessionID,
            source: .scooterBluetooth,
            method: .trapezoidalBetweenMeasurements,
            records: [durable]
        )

        let evidence = try RideDistanceEvidence(
            completedRide: completed,
            odometerCoverage: .complete,
            gpsRouteCoverage: .partial,
            liveDistanceAggregate: liveAggregate,
            transportGapOccurred: true
        )
        #expect(abs(try #require(evidence.scooterOdometerDeltaMeters) - 4_600) < 0.000_001)
        #expect(evidence.odometerCoverage == .complete)
        #expect(evidence.gpsRouteDistanceMeters == 5_000)
        #expect(evidence.gpsRouteCoverage == .partial)
        #expect(evidence.liveIntegratedDistanceMeters == 5_100)
        #expect(evidence.liveIntegratedCoverage == .partial)
    }
}
