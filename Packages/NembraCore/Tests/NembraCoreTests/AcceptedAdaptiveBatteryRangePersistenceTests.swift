import Foundation
import Testing
@testable import NembraCore

@Suite("Accepted adaptive battery range persistence")
struct AcceptedAdaptiveBatteryRangePersistenceTests {
    private func policy(
        minimumConsumedPercentagePoints: Double = 3,
        minimumDistanceMeters: Double = 300,
        outlierLowerEfficiencyRatio: Double = 0.4,
        outlierUpperEfficiencyRatio: Double = 2.5
    ) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: minimumConsumedPercentagePoints,
            minimumDistanceMeters: minimumDistanceMeters,
            recentWindowCapacity: 4,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: outlierLowerEfficiencyRatio,
            outlierUpperEfficiencyRatio: outlierUpperEfficiencyRatio,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: nil,
            lowSOCCautionThresholdPercent: nil,
            lowSOCEfficiencyMultiplier: nil,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func verifiedSOC(
        _ percentage: Double,
        epoch: UUID,
        sequence: UInt64,
        uptime: UInt64
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: .stateOfChargePercent(percentage),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: BatteryEvidenceReceiptIdentity(
                acquisitionEpoch: epoch,
                sequenceNumber: sequence
            ),
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: Double(sequence)),
            continuity: .continuous
        )
    }

    private func acceptedWindow(
        startPercentage: Double = 80,
        endPercentage: Double = 77,
        distanceMeters: Double = 360,
        coverage: BatteryRangeDistanceCoverage = .complete,
        epoch: UUID = UUID()
    ) throws -> AcceptedBatteryRangeLearningWindow {
        let p = try policy()
        var pipeline = AcceptedBatteryRangeLearningPipeline()
        _ = try pipeline.acceptBatteryObservation(
            try verifiedSOC(
                startPercentage,
                epoch: epoch,
                sequence: 1,
                uptime: 1_000
            ),
            policy: p
        )
        try pipeline.recordDistance(
            deltaMeters: distanceMeters,
            coverage: coverage
        )
        let result = try pipeline.acceptBatteryObservation(
            try verifiedSOC(
                endPercentage,
                epoch: epoch,
                sequence: 2,
                uptime: 2_000
            ),
            policy: p
        )
        return try #require(result.candidateLearningWindow)
    }

    @Test("verified accepted history round-trips through replay validation")
    func verifiedRoundTrip() throws {
        let p = try policy()
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        let sourceSessionID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: sourceSessionID,
            candidateOrdinal: 0
        )
        let window = try acceptedWindow(
            epoch: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )

        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )
        let learned = try persistent.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: plausibility
        )
        #expect(learned.alreadyCommitted == false)
        #expect(learned.learningResult.disposition == .accepted)
        #expect(persistent.acceptedWindowCount == 1)
        #expect(persistent.committedCandidateCount == 1)

        let encoded = try JSONEncoder().encode(persistent.checkpoint())
        let decoded = try JSONDecoder().decode(
            AcceptedAdaptiveBatteryRangePersistenceCheckpoint.self,
            from: encoded
        )
        let expectedScope = try AcceptedAdaptiveBatteryRangePersistenceScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )
        let restored = try AcceptedAdaptiveBatteryRangePersistentModel.restoringVerifiedVehicleIdentity(
            decoded,
            expectedScope: expectedScope
        )

        #expect(restored.acceptedWindowCount == 1)
        #expect(restored.committedCandidateCount == 1)
        #expect(restored.historicalConsumedPercentagePoints == 3)
        #expect(restored.typicalFullChargeRangeMeters(using: p) == 12_000)
        #expect(restored.checkpoint() == decoded)
    }

    @Test("exact committed candidate replay is idempotent")
    func exactDuplicateIsIdempotent() throws {
        let p = try policy()
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: UUID(uuidString: "22222222-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        let window = try acceptedWindow()
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )

        let first = try persistent.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: plausibility
        )
        let afterFirst = persistent.checkpoint()
        let second = try persistent.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: plausibility
        )

        #expect(first.alreadyCommitted == false)
        #expect(second.alreadyCommitted)
        #expect(second.learningResult.disposition == .accepted)
        #expect(persistent.acceptedWindowCount == 1)
        #expect(persistent.committedCandidateCount == 1)
        #expect(persistent.checkpoint() == afterFirst)
    }

    @Test("same durable candidate identity cannot be rebound to different evidence")
    func divergentDuplicateFailsClosed() throws {
        let p = try policy()
        let plausibility = try AcceptedAdaptiveRangePlausibilityPolicy(
            maximumFullChargeEquivalentMeters: 20_000
        )
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: UUID(uuidString: "33333333-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        let firstWindow = try acceptedWindow(distanceMeters: 360)
        let divergentWindow = try acceptedWindow(distanceMeters: 420)
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )
        _ = try persistent.ingest(
            firstWindow,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: plausibility
        )
        let before = persistent.checkpoint()

        #expect(throws: AcceptedAdaptiveBatteryRangePersistenceError.candidateIdentityConflict) {
            _ = try persistent.ingest(
                divergentWindow,
                candidateIdentity: identity,
                policy: p,
                plausibilityPolicy: plausibility
            )
        }
        #expect(persistent.checkpoint() == before)
        #expect(persistent.acceptedWindowCount == 1)
    }

    @Test("deferred first candidate is not consumed and may be retried with legitimate plausibility evidence")
    func deferredCandidateMayRetry() throws {
        let p = try policy()
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: UUID(uuidString: "44444444-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        let window = try acceptedWindow()
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )

        let deferred = try persistent.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: .deferredUntilVerifiedEvidence
        )
        #expect(deferred.learningResult.disposition == .deferred(.firstWindowPlausibilityUnverified))
        #expect(persistent.acceptedWindowCount == 0)
        #expect(persistent.committedCandidateCount == 0)

        let accepted = try persistent.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: 20_000
            )
        )
        #expect(accepted.learningResult.disposition == .accepted)
        #expect(accepted.alreadyCommitted == false)
        #expect(persistent.acceptedWindowCount == 1)
        #expect(persistent.committedCandidateCount == 1)
    }

    @Test("model-rejected candidate never enters durable accepted journal")
    func rejectedCandidateIsNotJournaled() throws {
        let p = try policy()
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: UUID(uuidString: "55555555-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        let incomplete = try acceptedWindow(coverage: .unknown)
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )

        let result = try persistent.ingest(
            incomplete,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: 20_000
            )
        )
        #expect(result.learningResult.disposition == .rejected(.incompleteDistanceEvidence))
        #expect(persistent.acceptedWindowCount == 0)
        #expect(persistent.committedCandidateCount == 0)
        #expect(persistent.checkpoint().acceptedCandidates.isEmpty)
    }

    @Test("verified scope rejects simulator candidate identity")
    func candidateAuthorityMismatchFailsClosed() throws {
        let p = try policy()
        let window = try acceptedWindow()
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.simulatorQA(
            sourceSessionID: UUID(uuidString: "66666666-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "verified-es80-fixture"
        )

        #expect(throws: AcceptedAdaptiveBatteryRangePersistenceError.candidateAuthorityMismatch) {
            _ = try persistent.ingest(
                window,
                candidateIdentity: identity,
                policy: p,
                plausibilityPolicy: try AcceptedAdaptiveRangePlausibilityPolicy(
                    maximumFullChargeEquivalentMeters: 20_000
                )
            )
        }
        #expect(persistent.committedCandidateCount == 0)
    }

    @Test("restore is bound to the independently supplied exact vehicle scope")
    func restoreScopeMismatchFailsClosed() throws {
        let p = try policy()
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.verifiedDurableSource(
            sourceSessionID: UUID(uuidString: "77777777-2222-3333-4444-555555555555")!,
            candidateOrdinal: 0
        )
        var persistent = try AcceptedAdaptiveBatteryRangePersistentModel.verifiedVehicleIdentity(
            vehicleIdentityKey: "vehicle-A"
        )
        _ = try persistent.ingest(
            try acceptedWindow(),
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: 20_000
            )
        )

        let wrongScope = try AcceptedAdaptiveBatteryRangePersistenceScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "vehicle-B"
        )
        #expect(throws: AcceptedAdaptiveBatteryRangePersistenceError.scopeMismatch) {
            _ = try AcceptedAdaptiveBatteryRangePersistentModel.restoringVerifiedVehicleIdentity(
                persistent.checkpoint(),
                expectedScope: wrongScope
            )
        }
    }

    @Test("simulator checkpoint remains simulator-only after Codable transit")
    func simulatorCheckpointDoesNotBecomeVerified() throws {
        let p = try policy()
        let sourceSessionID = UUID(uuidString: "88888888-2222-3333-4444-555555555555")!
        var simulator = try AcceptedAdaptiveBatteryRangePersistentModel.simulatorQA(
            vehicleIdentityKey: "sim-es80"
        )
        let window = try acceptedWindow()
        let identity = AcceptedAdaptiveBatteryRangeCandidateIdentity.simulatorQA(
            sourceSessionID: sourceSessionID,
            candidateOrdinal: 0
        )
        _ = try simulator.ingest(
            window,
            candidateIdentity: identity,
            policy: p,
            plausibilityPolicy: try AcceptedAdaptiveRangePlausibilityPolicy(
                maximumFullChargeEquivalentMeters: 20_000
            )
        )

        let bytes = try JSONEncoder().encode(simulator.checkpoint())
        let decoded = try JSONDecoder().decode(
            AcceptedAdaptiveBatteryRangePersistenceCheckpoint.self,
            from: bytes
        )
        let simulatorScope = try AcceptedAdaptiveBatteryRangePersistenceScope.simulatorQA(
            vehicleIdentityKey: "sim-es80"
        )
        let restoredSimulator = try AcceptedAdaptiveBatteryRangePersistentModel.restoringSimulatorQA(
            decoded,
            expectedScope: simulatorScope
        )
        #expect(restoredSimulator.acceptedWindowCount == 1)

        let verifiedScope = try AcceptedAdaptiveBatteryRangePersistenceScope.verifiedVehicleIdentity(
            vehicleIdentityKey: "sim-es80"
        )
        #expect(throws: AcceptedAdaptiveBatteryRangePersistenceError.scopeMismatch) {
            _ = try AcceptedAdaptiveBatteryRangePersistentModel.restoringVerifiedVehicleIdentity(
                decoded,
                expectedScope: verifiedScope
            )
        }
    }
}
