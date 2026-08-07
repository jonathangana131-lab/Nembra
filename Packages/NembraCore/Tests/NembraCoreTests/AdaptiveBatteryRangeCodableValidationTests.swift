import Foundation
import Testing
@testable import NembraCore

@Suite("Adaptive battery range Codable validation")
struct AdaptiveBatteryRangeCodableValidationTests {
    private func estimatedSOC(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .estimate,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func authoritativeSOC(_ percentage: Double, uptime: UInt64) throws -> BatterySOCReading {
        try BatterySOCReading(
            percentage: percentage,
            provenance: .authoritativeMeasurement,
            receivedAtUptimeNanoseconds: uptime
        )
    }

    private func validPolicy() throws -> AdaptiveBatteryRangePolicy {
        try AdaptiveBatteryRangePolicy(
            minimumConsumedPercentagePoints: 3,
            minimumDistanceMeters: 100,
            recentWindowCapacity: 3,
            recentWeight: 0.5,
            outlierLowerEfficiencyRatio: 0.4,
            outlierUpperEfficiencyRatio: 2.5,
            estimateDeadbandFraction: 0.05,
            estimateSmoothingFactor: 0.25,
            provisionalEfficiencyMetersPerPercentagePoint: 80,
            lowSOCCautionThresholdPercent: 20,
            lowSOCEfficiencyMultiplier: 0.9,
            lowConfidenceConsumedPercentagePoints: 10,
            normalConfidenceConsumedPercentagePoints: 30,
            highConfidenceConsumedPercentagePoints: 60
        )
    }

    private func jsonObject<T: Encodable>(for value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("estimated normalized SoC round-trips through generic Codable")
    func estimatedSOCRoundTrip() throws {
        let original = try estimatedSOC(73, uptime: 123)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatterySOCReading.self, from: data)
        #expect(decoded == original)
    }

    @Test("authoritative SoC cannot serialize into generic persistence")
    func authoritativeSOCEncodeRejected() throws {
        let reading = try authoritativeSOC(73, uptime: 123)
        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(reading)
        }
    }

    @Test("generic import cannot self-assert authoritative SoC")
    func authoritativeSOCDecodeRejected() throws {
        var object = try jsonObject(for: estimatedSOC(73, uptime: 123))
        object["provenance"] = BatterySOCProvenance.authoritativeMeasurement.rawValue
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatterySOCReading.self, from: data)
        }
    }

    @Test("decoded SoC cannot bypass normalized 0...100 validation")
    func corruptSOCRejected() throws {
        var object = try jsonObject(for: estimatedSOC(73, uptime: 123))
        object["percentage"] = 140.0
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatterySOCReading.self, from: data)
        }
    }

    @Test("non-authoritative learning window round-trips through validated initializers")
    func estimatedWindowRoundTrip() throws {
        let original = try BatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: estimatedSOC(80, uptime: 10),
            endSOC: estimatedSOC(70, uptime: 20)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatteryRangeLearningWindow.self, from: data)
        #expect(decoded == original)
    }

    @Test("authoritative learning window cannot serialize away its live authority boundary")
    func authoritativeWindowEncodeRejected() throws {
        let window = try BatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: authoritativeSOC(80, uptime: 10),
            endSOC: authoritativeSOC(70, uptime: 20)
        )

        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(window)
        }
    }

    @Test("decoded learning window cannot bypass monotonic time validation")
    func corruptWindowRejected() throws {
        let original = try BatteryRangeLearningWindow(
            distanceMeters: 1_200,
            distanceCoverage: .complete,
            transportGapOccurred: false,
            startSOC: estimatedSOC(80, uptime: 10),
            endSOC: estimatedSOC(70, uptime: 20)
        )
        var object = try jsonObject(for: original)
        var endSOC = try #require(object["endSOC"] as? [String: Any])
        endSOC["receivedAtUptimeNanoseconds"] = 10
        object["endSOC"] = endSOC
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatteryRangeLearningWindow.self, from: data)
        }
    }

    @Test("valid policy round-trips through the same throwing initializer")
    func validPolicyRoundTrip() throws {
        let original = try validPolicy()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdaptiveBatteryRangePolicy.self, from: data)
        #expect(decoded == original)
    }

    @Test("decoded policy cannot bypass recent-window capacity validation")
    func corruptPolicyRejected() throws {
        var object = try jsonObject(for: validPolicy())
        object["recentWindowCapacity"] = 0
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePolicy.self, from: data)
        }
    }

    @Test("decoded policy cannot bypass paired low-SoC configuration validation")
    func partialLowSOCPolicyRejected() throws {
        var object = try jsonObject(for: validPolicy())
        object.removeValue(forKey: "lowSOCEfficiencyMultiplier")
        let data = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(AdaptiveBatteryRangePolicy.self, from: data)
        }
    }
}
