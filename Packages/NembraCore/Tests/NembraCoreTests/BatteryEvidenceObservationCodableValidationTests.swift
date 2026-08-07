import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence observation Codable validation")
struct BatteryEvidenceObservationCodableValidationTests {
    @Test("decoded non-finite observation timestamp fails closed")
    func decodedNonFiniteTimestampIsRejected() {
        let payload = Data(
            #"{"value":{"field":"stateOfChargePercent","numericValue":50},"role":"simulationFixture","receivedAtUptimeNanoseconds":1,"receivedAtDate":"Infinity","continuity":"continuous"}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(BatteryEvidenceObservation.self, from: payload)
        }
    }
}
