import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence domain")
struct BatteryEvidenceDomainTests {
    private let epoch = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    private func receipt(_ sequence: UInt64 = 1) -> BatteryEvidenceReceiptIdentity {
        BatteryEvidenceReceiptIdentity(acquisitionEpoch: epoch, sequenceNumber: sequence)
    }

    private func observation(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: value,
            role: role,
            receiptIdentity: role == .verifiedVehicleMeasurement ? receipt() : nil,
            receivedAtUptimeNanoseconds: 42_000_000,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 123_456),
            continuity: continuity
        )
    }

    @Test("verified vehicle SoC is eligible as one adaptive-range anchor")
    func verifiedSOCIsRangeEvidence() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(73)
        let evidence = try observation(value: value, role: .verifiedVehicleMeasurement)

        #expect(evidence.receiptIdentity == receipt())
        #expect(evidence.isAuthoritativeVehicleMeasurement)
        #expect(evidence.isAdaptiveRangeSOCEvidence)
        #expect(!evidence.isVerifiedElectricalTelemetry)
    }

    @Test("stock-app battery percentage stays a correlation anchor")
    func stockAppSOCDoesNotBecomeMeasuredTelemetry() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(73)
        let evidence = try observation(value: value, role: .stockAppCorrelationAnchor)

        #expect(evidence.isStockAppCorrelationAnchor)
        #expect(!evidence.isAuthoritativeVehicleMeasurement)
        #expect(!evidence.isAdaptiveRangeSOCEvidence)
    }

    @Test("stock-app voltage current power and charging values cannot become verified electrical telemetry")
    func stockAppElectricalValuesStayUnverified() throws {
        let values = [
            try BatterySemanticValue.voltageVolts(40.7),
            try BatterySemanticValue.currentAmps(8.4),
            try BatterySemanticValue.powerWatts(341.9),
            try BatterySemanticValue.chargingState(false)
        ]

        for value in values {
            let evidence = try observation(value: value, role: .stockAppCorrelationAnchor)
            #expect(!evidence.isVerifiedElectricalTelemetry)
            #expect(!evidence.isAuthoritativeVehicleMeasurement)
        }
    }

    @Test("verified electrical values cross the production telemetry gate only after verification")
    func verifiedElectricalValuesCrossGate() throws {
        let values = [
            try BatterySemanticValue.voltageVolts(40.7),
            try BatterySemanticValue.currentAmps(8.4),
            try BatterySemanticValue.powerWatts(341.9),
            try BatterySemanticValue.chargingState(false)
        ]

        for value in values {
            let evidence = try observation(value: value, role: .verifiedVehicleMeasurement)
            #expect(evidence.receiptIdentity != nil)
            #expect(evidence.isVerifiedElectricalTelemetry)
        }
    }

    @Test("simulation estimate and presentation values never become physical measurements")
    func nonPhysicalRolesStayNonAuthoritative() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(64)
        let roles: [BatteryEvidenceRole] = [
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let evidence = try observation(value: value, role: role)
            #expect(!evidence.isAuthoritativeVehicleMeasurement)
            #expect(!evidence.isAdaptiveRangeSOCEvidence)
        }
    }

    @Test("SoC accepts legitimate fractional normalization without assuming ES80 resolution")
    func socDoesNotAssumeIntegerResolution() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(72.5)

        #expect(value.field == .stateOfChargePercent)
        #expect(value.numericValue == 72.5)
        #expect(value.booleanValue == nil)
    }

    @Test("SoC rejects out-of-range and non-finite values")
    func invalidSOCIsRejected() {
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.stateOfChargePercent(-0.1)
        }
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.stateOfChargePercent(100.1)
        }
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.stateOfChargePercent(.nan)
        }
    }

    @Test("voltage rejects negative and non-finite values without inventing an ES80 pack curve")
    func invalidVoltageIsRejected() {
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.voltageVolts(-0.1)
        }
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.voltageVolts(.infinity)
        }
    }

    @Test("current and power preserve sign until physical semantics are known")
    func currentAndPowerDoNotAssumeDirection() throws {
        let current = try BatterySemanticValue.currentAmps(-3.2)
        let power = try BatterySemanticValue.powerWatts(-128)

        #expect(current.numericValue == -3.2)
        #expect(power.numericValue == -128)
    }

    @Test("non-finite current and power are rejected")
    func nonFiniteElectricalValuesAreRejected() {
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.currentAmps(.nan)
        }
        #expect(throws: BatteryEvidenceValidationError.invalidSemanticValue) {
            _ = try BatterySemanticValue.powerWatts(.infinity)
        }
    }

    @Test("charging state is boolean semantic evidence")
    func chargingStateIsBoolean() throws {
        let charging = try BatterySemanticValue.chargingState(true)

        #expect(charging.field == .chargingState)
        #expect(charging.numericValue == nil)
        #expect(charging.booleanValue == true)
    }

    @Test("semantic value decoding revalidates persisted invariants")
    func semanticDecodeFailsClosed() throws {
        let valid = try BatterySemanticValue.stateOfChargePercent(81)
        let encoded = try JSONEncoder().encode(valid)
        let decoded = try JSONDecoder().decode(BatterySemanticValue.self, from: encoded)
        #expect(decoded == valid)

        let invalidSOC = Data(#"{"field":"stateOfChargePercent","numericValue":101}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatterySemanticValue.self, from: invalidSOC)
        }

        let invalidChargingShape = Data(#"{"field":"chargingState","numericValue":1}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(BatterySemanticValue.self, from: invalidChargingShape)
        }
    }

    @Test("observation timestamp must be finite")
    func invalidObservationTimestampIsRejected() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(50)

        #expect(throws: BatteryEvidenceValidationError.invalidTimestamp) {
            _ = try BatteryEvidenceObservation(
                value: value,
                role: .verifiedVehicleMeasurement,
                receiptIdentity: receipt(),
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: Date(timeIntervalSinceReferenceDate: .infinity)
            )
        }
    }

    @Test("verified observation without receipt identity fails closed")
    func verifiedObservationRequiresReceiptIdentity() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(50)

        #expect(throws: BatteryEvidenceValidationError.missingReceiptIdentity) {
            _ = try BatteryEvidenceObservation(
                value: value,
                role: .verifiedVehicleMeasurement,
                receiptIdentity: nil,
                receivedAtUptimeNanoseconds: 1,
                receivedAtDate: Date(timeIntervalSinceReferenceDate: 10)
            )
        }
    }

    @Test("continuity gaps are preserved instead of silently bridged")
    func continuityGapRequiresFreshAnchor() throws {
        let value = try BatterySemanticValue.stateOfChargePercent(55)
        let continuous = try observation(value: value, role: .verifiedVehicleMeasurement)
        let afterGap = try observation(
            value: value,
            role: .verifiedVehicleMeasurement,
            continuity: .afterUnobservedInterval
        )

        #expect(!continuous.requiresNewContinuityAnchor)
        #expect(afterGap.requiresNewContinuityAnchor)
        #expect(afterGap.isAdaptiveRangeSOCEvidence)
    }

    @Test("unbound nonauthoritative role and continuity survive Codable without truth promotion")
    func observationCodableRoundTripPreservesTruthRole() throws {
        let original = try observation(
            value: BatterySemanticValue.voltageVolts(39.8),
            role: .stockAppCorrelationAnchor,
            continuity: .afterUnobservedInterval
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BatteryEvidenceObservation.self, from: data)

        #expect(decoded == original)
        #expect(decoded.receiptIdentity == nil)
        #expect(decoded.role == .stockAppCorrelationAnchor)
        #expect(decoded.requiresNewContinuityAnchor)
        #expect(!decoded.isVerifiedElectricalTelemetry)
    }
}
