import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range persistence envelope")
struct AdaptiveBatteryRangePersistenceTests {
    private func policy(recentWindowCapacity: Int = 2) throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100,
            recentWindowCapacity: recentWindowCapacity,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func learningWindow(
        distanceMeters: Double,
        startPercentage: Double,
        endPercentage: Double,
        startUptime: UInt64,
        endUptime: UInt64
    ) throws -> BatteryRangeLearningWindow {
        try BatteryRangeLearningWindow(
            distanceMeters: distanceMeters,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: BatterySOCReading(
                percentage: startPercentage,
                provenance: .authoritativeMeasurement,
                receivedAtUptimeNanoseconds: startUptime
            ),
            endSOC: BatterySOCReading(
                percentage: endPercentage,
                provenance: .authoritativeMeasurement,
                receivedAtUptimeNanoseconds: endUptime
            )
        )
    }

    private func learnedModel() throws -> AdaptiveBatteryRangeModel {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try learningWindow(
                distanceMeters: 2_400,
                startPercentage: 80,
                endPercentage: 60,
                startUptime: 1,
                endUptime: 2
            ),
            policy: try policy()
        )
        #expect(result.disposition == .accepted)
        return model
    }

    private func mutatedJSON(
        for value: some Encodable,
        mutate: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(value)
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        try mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test("pristine and learned state round-trip with explicit schema")
    func validRoundTrips() throws {
        let pristine = try AdaptiveBatteryRangePersistedState(
            validating: AdaptiveBatteryRangeModel()
        )
        let pristineData = try JSONEncoder().encode(pristine)
        let decodedPristine = try JSONDecoder().decode(
            AdaptiveBatteryRangePersistedState.self,
            from: pristineData
        )
        #expect(decodedPristine == pristine)

        let learned = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let learnedData = try JSONEncoder().encode(learned)
        let decodedLearned = try JSONDecoder().decode(
            AdaptiveBatteryRangePersistedState.self,
            from: learnedData
        )

        #expect(decodedLearned == learned)
        #expect(decodedLearned.schemaVersion == AdaptiveBatteryRangePersistedState.currentSchemaVersion)
        #expect(decodedLearned.model.hasLearnedEfficiency)
    }

    @Test("multiple fully retained samples reconstruct weighted history")
    func multipleFullyRetainedSamplesRoundTrip() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(recentWindowCapacity: 2)

        let first = model.ingest(
            try learningWindow(
                distanceMeters: 2_000,
                startPercentage: 100,
                endPercentage: 80,
                startUptime: 1,
                endUptime: 2
            ),
            policy: p
        )
        let second = model.ingest(
            try learningWindow(
                distanceMeters: 2_400,
                startPercentage: 80,
                endPercentage: 60,
                startUptime: 3,
                endUptime: 4
            ),
            policy: p
        )

        #expect(first.disposition == .accepted)
        #expect(second.disposition == .accepted)
        #expect(model.acceptedWindowCount == 2)
        #expect(model.recentSamples.count == 2)
        #expect(model.historicalConsumedPercentagePoints == 40)
        #expect(model.historicalEfficiencyMetersPerPercentagePoint == 110)

        let state = try AdaptiveBatteryRangePersistedState(validating: model)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.model.recentSamples.count == decoded.model.acceptedWindowCount)
        #expect(decoded.model.historicalEfficiencyMetersPerPercentagePoint == 110)
    }

    @Test("maximum legitimate normalized consumption remains valid")
    func maximumLegitimateConsumptionAccepted() throws {
        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(
            try learningWindow(
                distanceMeters: 10_000,
                startPercentage: 100,
                endPercentage: 0,
                startUptime: 10,
                endUptime: 20
            ),
            policy: try policy()
        )
        #expect(result.disposition == .accepted)
        #expect(model.acceptedWindowCount == 1)
        #expect(model.historicalConsumedPercentagePoints == 100)

        let state = try AdaptiveBatteryRangePersistedState(validating: model)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)

        #expect(decoded == state)
        #expect(decoded.model.historicalConsumedPercentagePoints == 100)
    }

    @Test("truncated recent samples do not require reconstructing all history")
    func truncatedRecentHistoryAccepted() throws {
        var model = AdaptiveBatteryRangeModel()
        let p = try policy(recentWindowCapacity: 1)

        let first = model.ingest(
            try learningWindow(
                distanceMeters: 2_000,
                startPercentage: 100,
                endPercentage: 80,
                startUptime: 1,
                endUptime: 2
            ),
            policy: p
        )
        let second = model.ingest(
            try learningWindow(
                distanceMeters: 2_400,
                startPercentage: 80,
                endPercentage: 60,
                startUptime: 3,
                endUptime: 4
            ),
            policy: p
        )

        #expect(first.disposition == .accepted)
        #expect(second.disposition == .accepted)
        #expect(model.acceptedWindowCount == 2)
        #expect(model.recentSamples.count == 1)
        #expect(model.historicalConsumedPercentagePoints == 40)
        #expect(model.recentSamples[0].consumedPercentagePoints == 20)

        let state = try AdaptiveBatteryRangePersistedState(validating: model)
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data) == state)
    }

    @Test("unknown persistence schema fails closed")
    func unsupportedSchemaRejected() throws {
        let state = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let data = try mutatedJSON(for: state) { object in
            object["schemaVersion"] = 99
        }

        do {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)
            Issue.record("unsupported schema unexpectedly decoded")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .unsupportedSchemaVersion(99))
        }
    }

    @Test("shape-valid history cannot exceed normalized cumulative bounds")
    func impossibleHistoricalConsumptionRejected() throws {
        let learned = try learnedModel()
        let rawData = try mutatedJSON(for: learned) { object in
            object["historicalConsumedPercentagePoints"] = 150
        }

        // The model decoder correctly validates its own scalar/sample shape, but
        // this cross-field cumulative bound belongs to the persistence envelope.
        let shapeValidModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: rawData)
        #expect(shapeValidModel.acceptedWindowCount == 1)
        #expect(shapeValidModel.historicalConsumedPercentagePoints == 150)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: shapeValidModel)
            Issue.record("impossible cumulative history unexpectedly passed validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidHistoricalBounds)
        }
    }

    @Test("exhausted accepted-window counter cannot be restored into live learning")
    func exhaustedAcceptedWindowCounterRejected() throws {
        let learned = try learnedModel()
        let rawData = try mutatedJSON(for: learned) { object in
            object["acceptedWindowCount"] = Int.max
        }

        // The parent model decoder permits this shape because its retained sample
        // count still fits the accepted count. The persistence envelope must reject
        // it before a future accepted ingest evaluates `acceptedWindowCount += 1`.
        let shapeValidModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: rawData)
        #expect(shapeValidModel.acceptedWindowCount == Int.max)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: shapeValidModel)
            Issue.record("exhausted accepted-window counter unexpectedly passed validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidHistoricalBounds)
        }
    }

    @Test("retained recent evidence cannot exceed cumulative accepted history")
    func recentEvidenceCannotExceedHistory() throws {
        let learned = try learnedModel()
        let rawData = try mutatedJSON(for: learned) { object in
            object["historicalConsumedPercentagePoints"] = 5
        }

        let shapeValidModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: rawData)
        #expect(shapeValidModel.recentSamples.first?.consumedPercentagePoints == 20)
        #expect(shapeValidModel.historicalConsumedPercentagePoints == 5)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: shapeValidModel)
            Issue.record("recent evidence larger than history unexpectedly passed validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .recentEvidenceExceedsHistory)
        }
    }

    @Test("fully retained sample consumption must reconstruct cumulative history")
    func completeRecentConsumptionMismatchRejected() throws {
        let learned = try learnedModel()
        let rawData = try mutatedJSON(for: learned) { object in
            object["historicalConsumedPercentagePoints"] = 50
        }

        let shapeValidModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: rawData)
        #expect(shapeValidModel.acceptedWindowCount == 1)
        #expect(shapeValidModel.recentSamples.count == 1)
        #expect(shapeValidModel.recentSamples[0].consumedPercentagePoints == 20)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: shapeValidModel)
            Issue.record("fully retained consumption mismatch unexpectedly passed validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .completeRecentEvidenceDisagreesWithHistory)
        }
    }

    @Test("fully retained sample efficiency must reconstruct learned history")
    func completeRecentEfficiencyMismatchRejected() throws {
        let learned = try learnedModel()
        let rawData = try mutatedJSON(for: learned) { object in
            object["historicalEfficiencyMetersPerPercentagePoint"] = 999
        }

        let shapeValidModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: rawData)
        #expect(shapeValidModel.acceptedWindowCount == 1)
        #expect(shapeValidModel.recentSamples.count == 1)
        #expect(shapeValidModel.historicalEfficiencyMetersPerPercentagePoint == 999)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: shapeValidModel)
            Issue.record("fully retained efficiency mismatch unexpectedly passed validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .completeRecentEvidenceDisagreesWithHistory)
        }
    }

    @Test("envelope decode enforces cumulative bounds after model decode")
    func envelopeDecodeRejectsImpossibleCumulativeState() throws {
        let state = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let data = try mutatedJSON(for: state) { object in
            var model = object["model"] as! [String: Any]
            model["historicalConsumedPercentagePoints"] = 150
            object["model"] = model
        }

        do {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)
            Issue.record("impossible cumulative envelope unexpectedly decoded")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidHistoricalBounds)
        }
    }
}
