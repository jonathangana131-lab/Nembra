import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range persistence envelope")
struct AdaptiveBatteryRangePersistenceTests {
    private func policy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 2,
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

    private func learnedModel() throws -> AdaptiveBatteryRangeModel {
        let start = try BatterySOCReading(
            percentage: 80,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: 1
        )
        let end = try BatterySOCReading(
            percentage: 60,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: 2
        )
        let window = try BatteryRangeLearningWindow(
            distanceMeters: 2_400,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: start,
            endSOC: end
        )

        var model = AdaptiveBatteryRangeModel()
        let result = model.ingest(window, policy: try policy())
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
