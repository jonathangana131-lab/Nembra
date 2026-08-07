import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence authority construction")
struct BatteryEvidenceAuthorityConstructionTests {
    private let date = Date(timeIntervalSinceReferenceDate: 123_456)
    private let epoch = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

    private func receipt(_ sequence: UInt64 = 1) -> BatteryEvidenceReceiptIdentity {
        BatteryEvidenceReceiptIdentity(acquisitionEpoch: epoch, sequenceNumber: sequence)
    }

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

    @Test("verified package construction requires a live receipt identity")
    func verifiedConstructionRequiresReceiptIdentity() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(73)

        #expect(throws: BatteryEvidenceValidationError.missingReceiptIdentity) {
            _ = try BatteryEvidenceObservation(
                value: value,
                role: .verifiedVehicleMeasurement,
                receiptIdentity: nil,
                receivedAtUptimeNanoseconds: 10,
                receivedAtDate: date
            )
        }
    }

    @Test("public nonauthoritative factory stays receipt-unbound")
    func publicFactoryPreservesUnverifiedTruth() throws {
        let evidence = try BatteryEvidenceObservation.nonAuthoritative(
            value: BatterySemanticValue.voltageVolts(40.1),
            role: .stockAppCorrelationAnchor,
            receivedAtUptimeNanoseconds: 10,
            receivedAtDate: date,
            continuity: .afterUnobservedInterval
        )

        #expect(evidence.role == .stockAppCorrelationAnchor)
        #expect(evidence.receiptIdentity == nil)
        #expect(evidence.requiresNewContinuityAnchor)
        #expect(!evidence.isAuthoritativeVehicleMeasurement)
        #expect(!evidence.isVerifiedElectricalTelemetry)
    }

    @Test("package receipt sequencer produces one epoch and strict sequence")
    func sequencerProducesStrictReceiptOrder() throws {
        let sequencer = BatteryEvidenceReceiptSequencer(acquisitionEpoch: epoch)

        let first = try sequencer.nextReceiptIdentity()
        let second = try sequencer.nextReceiptIdentity()

        #expect(first == receipt(1))
        #expect(second == receipt(2))
        #expect(first.acquisitionEpoch == second.acquisitionEpoch)
        #expect(second.sequenceNumber > first.sequenceNumber)
    }

    @Test("sequencer aliases share one counter instead of forking receipt identity")
    func sequencerAliasesCannotForkCounter() throws {
        let sequencer = BatteryEvidenceReceiptSequencer(acquisitionEpoch: epoch)
        let alias = sequencer

        let first = try sequencer.nextReceiptIdentity()
        let second = try alias.nextReceiptIdentity()
        let third = try sequencer.nextReceiptIdentity()

        #expect(first == receipt(1))
        #expect(second == receipt(2))
        #expect(third == receipt(3))
    }

    @Test("receipt sequencer fails closed before UInt64 wrap")
    func sequencerNeverWraps() throws {
        let sequencer = BatteryEvidenceReceiptSequencer(
            acquisitionEpoch: epoch,
            startingSequenceNumber: UInt64.max - 1
        )

        let finalIssuable = try sequencer.nextReceiptIdentity()
        #expect(finalIssuable.sequenceNumber == UInt64.max - 1)
        #expect(throws: BatteryEvidenceReceiptSequencerError.sequenceExhausted) {
            _ = try sequencer.nextReceiptIdentity()
        }
    }

    @Test("generic Codable encoding refuses to serialize verified authority")
    func verifiedObservationDoesNotUseGenericEncoding() throws {
        let verified = try BatteryEvidenceObservation(
            value: BatterySemanticValue.stateOfChargePercent(73),
            role: .verifiedVehicleMeasurement,
            receiptIdentity: receipt(),
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

    @Test("generic Codable still round trips unbound nonauthoritative evidence")
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
        #expect(decoded.receiptIdentity == nil)
        #expect(!decoded.isAuthoritativeVehicleMeasurement)
    }

    @Test("generic Codable drops process-local receipt identity from bound nonauthoritative evidence")
    func genericCodableDoesNotPersistReceiptIdentity() throws {
        let bound = try BatteryEvidenceObservation(
            value: BatterySemanticValue.currentAmps(-2.5),
            role: .simulationFixture,
            receiptIdentity: receipt(44),
            receivedAtUptimeNanoseconds: 20,
            receivedAtDate: date
        )

        let data = try JSONEncoder().encode(bound)
        let text = try #require(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(BatteryEvidenceObservation.self, from: data)

        #expect(!text.contains("receiptIdentity"))
        #expect(bound.receiptIdentity == receipt(44))
        #expect(decoded.receiptIdentity == nil)
        #expect(decoded.role == .simulationFixture)
    }
}
