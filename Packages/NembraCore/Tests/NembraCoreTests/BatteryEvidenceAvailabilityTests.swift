import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence availability")
struct BatteryEvidenceAvailabilityTests {
    private func observation(
        field: BatteryEvidenceField,
        uptime: UInt64,
        numericValue: Double = 50,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        date: TimeInterval = 1_000
    ) throws -> BatteryEvidenceObservation {
        let value: BatterySemanticValue
        switch field {
        case .stateOfChargePercent:
            value = try BatterySemanticValue.stateOfChargePercent(numericValue)
        case .voltageVolts:
            value = try BatterySemanticValue.voltageVolts(numericValue)
        case .currentAmps:
            value = try BatterySemanticValue.currentAmps(numericValue)
        case .powerWatts:
            value = try BatterySemanticValue.powerWatts(numericValue)
        case .chargingState:
            value = try BatterySemanticValue.chargingState(numericValue != 0)
        }

        return try BatteryEvidenceObservation(
            value: value,
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSinceReferenceDate: date)
        )
    }

    @Test("zero freshness threshold is rejected")
    func invalidZeroThresholdIsRejected() {
        #expect(throws: BatteryEvidenceFreshnessPolicyError.invalidMaximumAge) {
            _ = try BatteryEvidenceFreshnessPolicy(
                maximumAgeNanosecondsByField: [.stateOfChargePercent: 0]
            )
        }
    }

    @Test("missing observation is unavailable regardless of policy")
    func missingObservationIsUnavailable() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.stateOfChargePercent: 10]
        )

        let availability = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: nil,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(availability == .unavailable)
    }

    @Test("missing field threshold preserves evidence as unclassified")
    func missingThresholdDoesNotGuessFreshness() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(maximumAgeNanosecondsByField: [:])
        let evidence = try observation(field: .voltageVolts, uptime: 90, numericValue: 40.2)

        let availability = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: evidence,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(availability == .unclassified(evidence))
        #expect(availability.observation == evidence)
        #expect(!availability.isFresh)
    }

    @Test("evidence exactly at maximum age remains fresh")
    func exactBoundaryIsFresh() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.stateOfChargePercent: 10]
        )
        let evidence = try observation(field: .stateOfChargePercent, uptime: 90, numericValue: 72)

        let availability = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: evidence,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(availability == .fresh(evidence, ageNanoseconds: 10))
        #expect(availability.isFresh)
    }

    @Test("evidence older than configured maximum age is stale but retained")
    func olderEvidenceIsStaleAndRetained() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.stateOfChargePercent: 10]
        )
        let evidence = try observation(field: .stateOfChargePercent, uptime: 89, numericValue: 72)

        let availability = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: evidence,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(availability == .stale(evidence, ageNanoseconds: 11))
        #expect(availability.observation == evidence)
        #expect(!availability.isFresh)
    }

    @Test("freshness thresholds are independent per field")
    func fieldThresholdsAreIndependent() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [
                .stateOfChargePercent: 20,
                .voltageVolts: 5
            ]
        )
        let soc = try observation(field: .stateOfChargePercent, uptime: 90, numericValue: 72)
        let voltage = try observation(field: .voltageVolts, uptime: 90, numericValue: 40.2)
        let currentSegment = BatteryEvidenceCurrentSegmentSnapshot(
            observationsByField: [
                .stateOfChargePercent: soc,
                .voltageVolts: voltage
            ]
        )

        let snapshot = try BatteryEvidenceAvailabilityEvaluator.snapshot(
            for: currentSegment,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(snapshot[.stateOfChargePercent] == .fresh(soc, ageNanoseconds: 10))
        #expect(snapshot[.voltageVolts] == .stale(voltage, ageNanoseconds: 10))
        #expect(snapshot[.currentAmps] == .unavailable)
    }

    @Test("future uptime evidence fails closed")
    func futureUptimeFailsClosed() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.stateOfChargePercent: 10]
        )
        let evidence = try observation(field: .stateOfChargePercent, uptime: 101)

        #expect(throws: BatteryEvidenceAvailabilityError.observationFromFutureUptime) {
            _ = try BatteryEvidenceAvailabilityEvaluator.availability(
                for: evidence,
                atUptimeNanoseconds: 100,
                policy: policy
            )
        }
    }

    @Test("wall clock movement cannot change uptime freshness classification")
    func wallClockIsNotFreshnessEvidence() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.stateOfChargePercent: 10]
        )
        let earlierDate = try observation(
            field: .stateOfChargePercent,
            uptime: 95,
            numericValue: 72,
            date: 2_000
        )
        let laterDate = try observation(
            field: .stateOfChargePercent,
            uptime: 95,
            numericValue: 72,
            date: 1_000
        )

        let first = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: earlierDate,
            atUptimeNanoseconds: 100,
            policy: policy
        )
        let second = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: laterDate,
            atUptimeNanoseconds: 100,
            policy: policy
        )

        #expect(first == .fresh(earlierDate, ageNanoseconds: 5))
        #expect(second == .fresh(laterDate, ageNanoseconds: 5))
    }

    @Test("freshness classification never promotes stock-app evidence")
    func freshnessDoesNotPromoteTruthRole() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(
            maximumAgeNanosecondsByField: [.voltageVolts: 10]
        )
        let evidence = try observation(
            field: .voltageVolts,
            uptime: 95,
            numericValue: 40.2,
            role: .stockAppCorrelationAnchor
        )

        let availability = try BatteryEvidenceAvailabilityEvaluator.availability(
            for: evidence,
            atUptimeNanoseconds: 100,
            policy: policy
        )
        let retained = try #require(availability.observation)

        #expect(availability.isFresh)
        #expect(retained.role == .stockAppCorrelationAnchor)
        #expect(!retained.isVerifiedElectricalTelemetry)
    }

    @Test("empty policy leaves every present field unclassified")
    func emptyPolicyIsExplicitlyUnclassified() throws {
        let policy = try BatteryEvidenceFreshnessPolicy(maximumAgeNanosecondsByField: [:])
        let soc = try observation(field: .stateOfChargePercent, uptime: 50, numericValue: 70)
        let power = try observation(field: .powerWatts, uptime: 50, numericValue: 200)
        let currentSegment = BatteryEvidenceCurrentSegmentSnapshot(
            observationsByField: [
                .stateOfChargePercent: soc,
                .powerWatts: power
            ]
        )

        let snapshot = try BatteryEvidenceAvailabilityEvaluator.snapshot(
            for: currentSegment,
            atUptimeNanoseconds: 5_000,
            policy: policy
        )

        #expect(snapshot[.stateOfChargePercent] == .unclassified(soc))
        #expect(snapshot[.powerWatts] == .unclassified(power))
        #expect(snapshot[.voltageVolts] == .unavailable)
    }
}
