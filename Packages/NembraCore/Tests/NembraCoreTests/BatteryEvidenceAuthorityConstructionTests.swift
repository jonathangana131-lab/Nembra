import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence authority construction")
struct BatteryEvidenceAuthorityConstructionTests {
    private let date = Date(timeIntervalSinceReferenceDate: 123_456)

    @Test("public nonauthoritative factory cannot claim verified vehicle authority")
    func publicFactoryRejectsVerifiedRole() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(73)

        #expect(throws: BatteryEvidenceValidationError.invalidEvidenceRole) {
            _ = try BatteryEvidenceObservation.nonAuthoritative(
                value: value,
                role: .verifiedVehicleMeasurement,
                receivedAtUptimeNanoseconds: 10,
                receivedAtDate: date
            )
        }
    }

    @Test("public nonauthoritative factory preserves allowed role and continuity")
    func publicFactoryPreservesUnverifiedTruth() throws {
        let evidence = try BatteryEvidenceObservation.nonAuthoritative(
            value: BatterySemanticValue.voltageVolts(40.1),
            role: .stockAppCorrelationAnchor,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: date,
            continuity: .afterUnobservedInterval
        )

        #expect(evidence.role == .stockAppCorrelationAnchor)
        #expect(evidence.requiresNewContinuityAnchor)
        #expect(!evidence.isAuthoritativeVehicleMeasurement)
        #expect(!evidence.isVerifiedElectricalTelemetry)
    }

    @Test("generic Codable encoding refuses to serialize verified authority")
    func verifiedObservationDoesNotUseGenericEncoding() throws {
        let verified = try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(73),
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: date
        )

        #expect(throws: EncodingError.self) {
            _ = try JSONEncoder().encode(verified)
        }
    }

    @Test("generic Codable decoding cannot self-assert verified authority")
    func verifiedRoleCannotEnterThroughGenericDecode() throws {
        let unverified = try BatteryEvidenceObservation.nonAuthoritative(
            value: BatterySemanticValue.stateOfChargePercent(73),
            role: .stockAppCorrelationAnchor,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: date
        )
        let data = try JSONEncoder().encode(unverified)
        let text = try #require(String(data: data, encoding: .utf8))
        let forged = try #require(
            text.replacingOccurrences(
                of: BatteryEvidenceRole.stockAppCorrelationAnchor.rawValue,
                with: BatteryEvidenceRole.verifiedVehicleMeasurement.rawValue
            ).data(using: .utf8)
        )

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatteryEvidenceObservation.self, from: forged)
        }
    }

    @Test("generic Codable still round trips nonauthoritative evidence")
    func nonAuthoritativeRoundTripRemainsAvailable() throws {
        let original = try BatteryEvidenceObservation.nonAuthoritative(
            value: BatterySemanticValue.currentAmps(-2.5),
            role: .simulationFixture,
            receivedAtUptimeNanoseconds: 20,
            receivedAtDate: date,
            continuity: .afterUnobservedInterval
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatteryEvidenceObservation.self, from: data)

        #expect(decoded == original)
        #expect(!decoded.isAuthoritativeVehicleMeasurement)
    }
}
