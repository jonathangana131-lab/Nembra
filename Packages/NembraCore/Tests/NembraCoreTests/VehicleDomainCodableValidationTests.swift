import Foundation
import Testing
@testable import NembraCore

@Suite("Vehicle domain Codable validation")
struct VehicleDomainCodableValidationTests {
    @Test("speed-limit range round-trips when ordered")
    func speedLimitRangeRoundTrip() throws {
        let original = SpeedLimitRange(
            minimumKilometersPerHour: 5,
            maximumKilometersPerHour: 15
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeedLimitRange.self, from: data)

        #expect(decoded == original)
        #expect(decoded.contains(5))
        #expect(decoded.contains(15))
        #expect(!decoded.contains(16))
    }

    @Test("decoded inverted speed-limit range fails closed")
    func invertedSpeedLimitRangeIsRejected() throws {
        let data = try #require(
            """
            {
              "minimumKilometersPerHour": 20,
              "maximumKilometersPerHour": 5
            }
            """.data(using: .utf8)
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SpeedLimitRange.self, from: data)
        }
    }
}
