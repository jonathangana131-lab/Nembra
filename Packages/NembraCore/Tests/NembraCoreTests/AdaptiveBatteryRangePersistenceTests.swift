import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range persistence")
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

    @Test("pristine and learned state round-trip through the validated envelope")
    func validRoundTrips() throws {
        let pristine = try AdaptiveBatteryRangePersistedState(
            validating: AdaptiveBatteryRangeModel()
        )
        let pristineData = try JSONEncoder().encode(pristine)
        #expect(try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: pristineData) == pristine)

        let learned = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let learnedData = try JSONEncoder().encode(learned)
        let decoded = try JSONDecoder().decode(
            AdaptiveBatteryRangePersistedState.self,
            from: learnedData
        )

        #expect(decoded == learned)
        #expect(decoded.schemaVersion == AdaptiveBatteryRangePersistedState.currentSchemaVersion)
        #expect(decoded.model.hasLearnedEfficiency)
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

    @Test("corrupted historical accumulators cannot become learned range truth")
    func corruptedHistoricalStateRejected() throws {
        let state = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let data = try mutatedJSON(for: state) { object in
            var model = object["model"] as! [String: Any]
            model["historicalConsumedPercentagePoints"] = -20
            object["model"] = model
        }

        do {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)
            Issue.record("negative historical consumption unexpectedly decoded")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidHistoricalState)
        }
    }

    @Test("decoded recent samples must preserve their distance/consumption identity")
    func inconsistentRecentSampleRejected() throws {
        let state = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let data = try mutatedJSON(for: state) { object in
            var model = object["model"] as! [String: Any]
            var samples = model["recentSamples"] as! [[String: Any]]
            samples[0]["metersPerPercentagePoint"] = 999
            model["recentSamples"] = samples
            object["model"] = model
        }

        do {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)
            Issue.record("inconsistent efficiency sample unexpectedly decoded")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidRecentSample(0))
        }
    }

    @Test("recent retained evidence cannot exceed total accepted battery history")
    func recentEvidenceCannotExceedHistory() throws {
        let state = try AdaptiveBatteryRangePersistedState(validating: learnedModel())
        let data = try mutatedJSON(for: state) { object in
            var model = object["model"] as! [String: Any]
            model["historicalConsumedPercentagePoints"] = 5
            object["model"] = model
        }

        do {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePersistedState.self, from: data)
            Issue.record("recent evidence larger than historical evidence unexpectedly decoded")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .recentEvidenceExceedsHistory)
        }
    }

    @Test("validation catches impossible raw Codable state before restoration")
    func validatesLegacyRawModelBeforeUse() throws {
        let model = try learnedModel()
        let data = try mutatedJSON(for: model) { object in
            object["acceptedWindowCount"] = 0
        }

        // Synthesized Codable can reconstruct this impossible state, which is why
        // app persistence must cross the validated envelope before reuse.
        let corruptedRawModel = try JSONDecoder().decode(AdaptiveBatteryRangeModel.self, from: data)
        #expect(corruptedRawModel.acceptedWindowCount == 0)
        #expect(corruptedRawModel.recentSamples.isEmpty == false)

        do {
            _ = try AdaptiveBatteryRangePersistedState(validating: corruptedRawModel)
            Issue.record("impossible raw model unexpectedly passed persistence validation")
        } catch let error as AdaptiveBatteryRangePersistedStateError {
            #expect(error == .invalidAcceptedWindowCount)
        }
    }
}
