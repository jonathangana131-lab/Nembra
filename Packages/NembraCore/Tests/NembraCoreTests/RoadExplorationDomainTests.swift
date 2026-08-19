import Foundation
import Testing
@testable import NembraCore

@Suite("Road exploration evidence and coverage")
struct RoadExplorationDomainTests {
    private let rideA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let rideB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let rideC = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let runA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let runB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let runC = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let runD = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let runE = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let runF = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    private func key(version: String = "graph-1") throws -> RoadDatasetKey {
        try RoadDatasetKey(
            providerID: "fixture-provider",
            regionID: "fixture-city",
            graphVersion: version
        )
    }

    private func dataset(
        version: String = "graph-1",
        reviewState: RoadDatasetLicenseReviewState = .approved
    ) throws -> RoadDatasetIdentity {
        let reviewReference = reviewState == .pending ? nil : "legal-review-2026-08"
        return try RoadDatasetIdentity(
            key: key(version: version),
            license: RoadDatasetLicense(
                licenseIdentifier: "fixture-road-license",
                licenseVersion: "1",
                attributionText: "Fixture road data",
                attributionURL: URL(string: "https://example.invalid/road-license"),
                reviewState: reviewState,
                reviewReference: reviewReference
            )
        )
    }

    private func access(
        _ disposition: RoadAccessEligibilityDisposition
    ) throws -> RoadAccessEligibility {
        try RoadAccessEligibility(
            disposition: disposition,
            rationaleCode: disposition == .eligible ? nil : "fixture-\(disposition.rawValue)"
        )
    }

    private func segment(
        _ canonicalID: String,
        datasetKey: RoadDatasetKey,
        length: Double = 100,
        directionality: RoadSegmentDirectionality = .bidirectional,
        accessDisposition: RoadAccessEligibilityDisposition = .eligible
    ) throws -> RoadSegmentDefinition {
        try RoadSegmentDefinition(
            id: RoadSegmentID(datasetKey: datasetKey, canonicalID: canonicalID),
            canonicalLengthMeters: length,
            directionality: directionality,
            classification: "fixture-residential",
            access: access(accessDisposition),
            areaMembershipIDs: ["fixture-district", "fixture-city"]
        )
    }

    private func catalog(
        dataset: RoadDatasetIdentity,
        segments: [RoadSegmentDefinition]
    ) throws -> RoadNetworkCatalog {
        try RoadNetworkCatalog(dataset: dataset, segments: segments)
    }

    private func matcher(_ version: String = "matcher-1") throws -> RoadMatcherIdentity {
        try RoadMatcherIdentity(matcherID: "fixture-matcher", version: version)
    }

    private func policy(
        version: String = "coverage-v1",
        confidence: Double = 0.8,
        minimumLength: Double = 0
    ) throws -> RoadCoveragePolicy {
        try RoadCoveragePolicy(
            version: version,
            minimumAcceptedConfidence: confidence,
            minimumVerifiedClaimLengthMeters: minimumLength
        )
    }

    private func interval(_ lower: Double, _ upper: Double) throws -> RoadCoverageInterval {
        try RoadCoverageInterval(lowerBound: lower, upperBound: upper)
    }

    private func matchedClaim(
        segment: RoadSegmentDefinition,
        intervals: [RoadCoverageInterval],
        firstPoint: UInt64 = 0,
        lastPoint: UInt64 = 4,
        confidence: Double = 0.95,
        ambiguity: RoadMatchAmbiguity = .none,
        direction: RoadTraversalDirectionEvidence = .canonical,
        rideEvidence: RoadRideEvidenceStatus = .independentlyVerifiedRiding,
        disposition: RoadMatchDisposition = .matched
    ) throws -> RoadMatchClaim {
        try RoadMatchClaim(
            sourcePointRange: RoadSourcePointRange(
                firstIndex: firstPoint,
                lastIndex: lastPoint
            ),
            disposition: disposition,
            segmentID: segment.id,
            confidence: confidence,
            ambiguity: ambiguity,
            directionEvidence: direction,
            rideEvidenceStatus: rideEvidence,
            coveredIntervals: intervals
        )
    }

    private func unmatchedClaim(
        firstPoint: UInt64 = 0,
        lastPoint: UInt64 = 4
    ) throws -> RoadMatchClaim {
        try RoadMatchClaim(
            sourcePointRange: RoadSourcePointRange(
                firstIndex: firstPoint,
                lastIndex: lastPoint
            ),
            disposition: .unmatched,
            segmentID: nil,
            confidence: 0,
            ambiguity: .none,
            directionEvidence: .unknown,
            rideEvidenceStatus: .independentlyVerifiedRiding,
            coveredIntervals: []
        )
    }

    private func matchRun(
        runUUID: UUID,
        rideID: UUID,
        digestCharacter: Character,
        datasetKey: RoadDatasetKey,
        matcher: RoadMatcherIdentity,
        policyVersion: String = "coverage-v1",
        claims: [RoadMatchClaim]
    ) throws -> RoadMatchRun {
        let digest = try RoadRouteDigest(
            hexValue: String(repeating: String(digestCharacter), count: 64)
        )
        let binding = try RoadMatchRunBinding(
            rawRouteDigest: digest,
            datasetKey: datasetKey,
            matcher: matcher,
            coveragePolicyVersion: policyVersion
        )
        return try RoadMatchRun(
            id: RoadMatchRunID(runUUID: runUUID, binding: binding),
            rideID: rideID,
            claims: claims
        )
    }

    @Test("overlapping partial blocks union by canonical road interval")
    func overlappingPartialBlocks() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let run = try matchRun(
            runUUID: runA,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [
                matchedClaim(
                    segment: road,
                    intervals: [interval(0, 0.5)],
                    firstPoint: 0,
                    lastPoint: 5
                ),
                matchedClaim(
                    segment: road,
                    intervals: [interval(0.3, 0.8)],
                    firstPoint: 6,
                    lastPoint: 12
                )
            ]
        )
        try ledger.accept(run)

        let result = try ledger.aggregate()
        #expect(result.evidenceState == .verified)
        #expect(abs(result.verifiedCoveredLengthMeters - 80) < 0.000_001)
        #expect(abs((result.progressFraction ?? -1) - 0.8) < 0.000_001)
        #expect(result.segmentCoverage.first?.coveredIntervals == [try interval(0, 0.8)])
        #expect(result.explorationState(for: road) == .partiallyVerified)
    }

    @Test("out and back travel covers direction-agnostic geometry once")
    func directionAgnosticOutAndBack() throws {
        let data = try dataset()
        let road = try segment(
            "road-a",
            datasetKey: data.key,
            directionality: .bidirectional
        )
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0, 1)],
                        firstPoint: 0,
                        lastPoint: 10,
                        direction: .canonical
                    ),
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0, 1)],
                        firstPoint: 11,
                        lastPoint: 20,
                        direction: .reverse
                    )
                ]
            )
        )

        let result = try ledger.aggregate()
        #expect(result.verifiedClaimCount == 2)
        #expect(result.verifiedCoveredLengthMeters == 100)
        #expect(result.progressFraction == 1)
        #expect(result.explorationState(for: road) == .fullyVerified)
    }

    @Test("parallel-road ambiguity is retained but never counted")
    func parallelRoadAmbiguityRejected() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0, 1)],
                        ambiguity: .parallelRoads
                    )
                ]
            )
        )

        let result = try ledger.aggregate()
        #expect(result.evidenceState == .partial)
        #expect(result.verifiedCoveredLengthMeters == 0)
        #expect(result.rejectedMatches.ambiguous == 1)
        #expect(result.explorationState(for: road) == .eligibleUnexplored)
        #expect(result.accessibilitySummary.accessibilityValue.contains("unmatched or unverified"))
    }

    @Test("exact replay is a no-op and conflicting deterministic output fails closed")
    func replayAndConflict() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let accepted = try matchRun(
            runUUID: runA,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [matchedClaim(segment: road, intervals: [interval(0, 0.5)])]
        )
        #expect(try ledger.accept(accepted) == .inserted)
        #expect(try ledger.accept(accepted) == .replayedNoOp)
        #expect(ledger.retainedRunCount == 1)

        let conflictingUUIDReplay = try matchRun(
            runUUID: runA,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [matchedClaim(segment: road, intervals: [interval(0, 0.6)])]
        )
        #expect(throws: RoadExplorationDomainError.matchRunConflict(runA)) {
            _ = try ledger.accept(conflictingUUIDReplay)
        }

        let semanticReplay = try matchRun(
            runUUID: runB,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: accepted.claims
        )
        #expect(try ledger.accept(semanticReplay) == .replayedNoOp)
        #expect(ledger.retainedRunCount == 1)

        let conflictingBindingReplay = try matchRun(
            runUUID: runB,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [matchedClaim(segment: road, intervals: [interval(0, 0.7)])]
        )
        #expect(
            throws: RoadExplorationDomainError.matchRunBindingConflict(
                existing: runA,
                incoming: runB
            )
        ) {
            _ = try ledger.accept(conflictingBindingReplay)
        }
        #expect(ledger.retainedRunCount == 1)
    }

    @Test("deleting one ride recomputes union while shared coverage remains")
    func sharedCoverageDeletion() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [matchedClaim(segment: road, intervals: [interval(0, 0.7)])]
            )
        )
        try ledger.accept(
            matchRun(
                runUUID: runB,
                rideID: rideB,
                digestCharacter: "b",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [matchedClaim(segment: road, intervals: [interval(0.3, 1)])]
            )
        )
        #expect(try ledger.aggregate().verifiedCoveredLengthMeters == 100)

        #expect(ledger.deleteRide(rideA) == 1)
        let remaining = try ledger.aggregate()
        #expect(abs(remaining.verifiedCoveredLengthMeters - 70) < 0.000_001)
        #expect(remaining.segmentCoverage.first?.coveredIntervals == [try interval(0.3, 1)])
        #expect(remaining.segmentCoverage.first?.contributingRideIDs == [rideB])
    }

    @Test("dataset, matcher, and policy revisions remain separated until reprocessed")
    func versionSeparationAndReprocessing() throws {
        let oldData = try dataset(version: "graph-1")
        let currentData = try dataset(version: "graph-2")
        let oldRoad = try segment("road-a", datasetKey: oldData.key)
        let currentRoad = try segment("road-a-v2", datasetKey: currentData.key)
        let currentMatcher = try matcher("matcher-2")
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: currentData, segments: [currentRoad]),
            policy: try policy(version: "coverage-v2"),
            currentMatcher: currentMatcher
        )

        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: oldData.key,
                matcher: currentMatcher,
                policyVersion: "coverage-v2",
                claims: [matchedClaim(segment: oldRoad, intervals: [interval(0, 0.3)])]
            )
        )
        try ledger.accept(
            matchRun(
                runUUID: runB,
                rideID: rideB,
                digestCharacter: "b",
                datasetKey: currentData.key,
                matcher: matcher("matcher-1"),
                policyVersion: "coverage-v2",
                claims: [matchedClaim(segment: currentRoad, intervals: [interval(0.3, 0.6)])]
            )
        )
        try ledger.accept(
            matchRun(
                runUUID: runC,
                rideID: rideC,
                digestCharacter: "c",
                datasetKey: currentData.key,
                matcher: currentMatcher,
                policyVersion: "coverage-v1",
                claims: [matchedClaim(segment: currentRoad, intervals: [interval(0.6, 1)])]
            )
        )

        let outdated = try ledger.aggregate()
        #expect(outdated.evidenceState == .outdated)
        #expect(outdated.verifiedCoveredLengthMeters == 0)
        #expect(outdated.reprocessing.unresolvedOutdatedRunCount == 3)
        #expect(Set(outdated.reprocessing.reasons) == [
            .datasetChanged,
            .matcherChanged,
            .policyChanged
        ])

        try ledger.accept(
            matchRun(
                runUUID: runD,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: currentData.key,
                matcher: currentMatcher,
                policyVersion: "coverage-v2",
                claims: [matchedClaim(segment: currentRoad, intervals: [interval(0, 0.3)])]
            )
        )
        try ledger.accept(
            matchRun(
                runUUID: runE,
                rideID: rideB,
                digestCharacter: "b",
                datasetKey: currentData.key,
                matcher: currentMatcher,
                policyVersion: "coverage-v2",
                claims: [matchedClaim(segment: currentRoad, intervals: [interval(0.3, 0.6)])]
            )
        )
        try ledger.accept(
            matchRun(
                runUUID: runF,
                rideID: rideC,
                digestCharacter: "c",
                datasetKey: currentData.key,
                matcher: currentMatcher,
                policyVersion: "coverage-v2",
                claims: [matchedClaim(segment: currentRoad, intervals: [interval(0.6, 1)])]
            )
        )

        let reprocessed = try ledger.aggregate()
        #expect(reprocessed.reprocessing.isRequired == false)
        #expect(reprocessed.evidenceState == .verified)
        #expect(reprocessed.verifiedCoveredLengthMeters == 100)
    }

    @Test("private, ineligible, and unknown roads stay outside the denominator")
    func eligibilityDefinesDenominator() throws {
        let data = try dataset()
        let eligible = try segment("eligible", datasetKey: data.key, length: 100)
        let privateRoad = try segment(
            "private",
            datasetKey: data.key,
            length: 50,
            accessDisposition: .ineligible
        )
        let unknown = try segment(
            "unknown",
            datasetKey: data.key,
            length: 70,
            accessDisposition: .unknown
        )
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [eligible, privateRoad, unknown]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [
                    matchedClaim(segment: eligible, intervals: [interval(0, 1)], firstPoint: 0, lastPoint: 4),
                    matchedClaim(segment: privateRoad, intervals: [interval(0, 1)], firstPoint: 5, lastPoint: 9),
                    matchedClaim(segment: unknown, intervals: [interval(0, 1)], firstPoint: 10, lastPoint: 14)
                ]
            )
        )

        let result = try ledger.aggregate()
        #expect(result.eligibleLengthMeters == 100)
        #expect(result.eligibleSegmentCount == 1)
        #expect(result.verifiedCoveredLengthMeters == 100)
        #expect(result.progressFraction == 1)
        #expect(result.rejectedMatches.ineligibleOrUnknownSegment == 2)
        #expect(result.evidenceState == .partial)
        #expect(result.explorationState(for: privateRoad) == .ineligibleOrUnknown)
        #expect(result.explorationState(for: unknown) == .ineligibleOrUnknown)
    }

    @Test("confidence threshold is injected and inclusive at the boundary")
    func confidenceThreshold() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(confidence: 0.8),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0, 0.5)],
                        firstPoint: 0,
                        lastPoint: 5,
                        confidence: 0.799_999
                    ),
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0.5, 1)],
                        firstPoint: 6,
                        lastPoint: 12,
                        confidence: 0.8
                    )
                ]
            )
        )

        let result = try ledger.aggregate()
        #expect(result.verifiedCoveredLengthMeters == 50)
        #expect(result.rejectedMatches.belowConfidenceThreshold == 1)
        #expect(result.verifiedClaimCount == 1)
        #expect(result.evidenceState == .partial)
    }

    @Test("unmatched route gaps never bridge into road coverage")
    func unmatchedGaps() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        try ledger.accept(
            matchRun(
                runUUID: runA,
                rideID: rideA,
                digestCharacter: "a",
                datasetKey: data.key,
                matcher: matcher(),
                claims: [
                    matchedClaim(
                        segment: road,
                        intervals: [interval(0, 0.4)],
                        firstPoint: 0,
                        lastPoint: 5
                    ),
                    unmatchedClaim(firstPoint: 6, lastPoint: 12)
                ]
            )
        )

        let result = try ledger.aggregate()
        #expect(result.verifiedCoveredLengthMeters == 40)
        #expect(result.segmentCoverage.first?.coveredIntervals == [try interval(0, 0.4)])
        #expect(result.rejectedMatches.unmatched == 1)
        #expect(result.evidenceState == .partial)
    }

    @Test("license review gates denominator, attribution, and unavailable truth")
    func licenseAndUnavailableTruth() throws {
        let pendingData = try dataset(reviewState: .pending)
        let pendingRoad = try segment("road-a", datasetKey: pendingData.key)
        let pendingLedger = RoadCoverageLedger(
            catalog: try catalog(dataset: pendingData, segments: [pendingRoad]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let pending = try pendingLedger.aggregate()
        #expect(pending.evidenceState == .unavailable)
        #expect(pending.unavailableReason == .licenseReviewPending)
        #expect(pending.eligibleLengthMeters == nil)
        #expect(pending.progressFraction == nil)
        #expect(pending.requiredAttribution == "Fixture road data")
        #expect(pending.accessibilitySummary.accessibilityValue.contains("license review"))

        let approvedData = try dataset()
        let approvedRoad = try segment("road-a", datasetKey: approvedData.key)
        let emptyLedger = RoadCoverageLedger(
            catalog: try catalog(dataset: approvedData, segments: [approvedRoad]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let noEvidence = try emptyLedger.aggregate()
        #expect(noEvidence.evidenceState == .noEvidence)
        #expect(noEvidence.verifiedCoveredLengthMeters == 0)
        #expect(noEvidence.progressFraction == 0)
        #expect(noEvidence.accessibilitySummary.accessibilityValue.contains("No verified roads yet"))

        let excludedRoad = try segment(
            "private",
            datasetKey: approvedData.key,
            accessDisposition: .ineligible
        )
        let noEligibleLedger = RoadCoverageLedger(
            catalog: try catalog(dataset: approvedData, segments: [excludedRoad]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let noEligible = try noEligibleLedger.aggregate()
        #expect(noEligible.evidenceState == .unavailable)
        #expect(noEligible.unavailableReason == .noEligibleRoads)
    }

    @Test("newly verified intervals emit one replay-safe presentation-neutral discovery delta")
    func discoveryDelta() throws {
        let data = try dataset()
        let road = try segment("road-a", datasetKey: data.key)
        var ledger = RoadCoverageLedger(
            catalog: try catalog(dataset: data, segments: [road]),
            policy: try policy(),
            currentMatcher: try matcher()
        )
        let firstRun = try matchRun(
            runUUID: runA,
            rideID: rideA,
            digestCharacter: "a",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [matchedClaim(segment: road, intervals: [interval(0, 0.6)])]
        )
        let first = try ledger.acceptProjectingDiscoveries(firstRun)
        #expect(first.acceptance == .inserted)
        #expect(first.discoveryEvents.count == 1)
        #expect(first.discoveryEvents.first?.newlyVerifiedIntervals == [try interval(0, 0.6)])
        #expect(first.discoveryEvents.first?.newlyVerifiedLengthMeters == 60)
        #expect(try ledger.aggregate().explorationState(for: road) == .partiallyVerified)

        let replay = try ledger.acceptProjectingDiscoveries(firstRun)
        #expect(replay.acceptance == .replayedNoOp)
        #expect(replay.discoveryEvents.isEmpty)

        let secondRun = try matchRun(
            runUUID: runB,
            rideID: rideB,
            digestCharacter: "b",
            datasetKey: data.key,
            matcher: matcher(),
            claims: [matchedClaim(segment: road, intervals: [interval(0.4, 1)])]
        )
        let second = try ledger.acceptProjectingDiscoveries(secondRun)
        #expect(second.discoveryEvents.first?.newlyVerifiedIntervals == [try interval(0.6, 1)])
        #expect(abs((second.discoveryEvents.first?.newlyVerifiedLengthMeters ?? -1) - 40) < 0.000_001)
        #expect(try ledger.aggregate().explorationState(for: road) == .fullyVerified)
    }
}
