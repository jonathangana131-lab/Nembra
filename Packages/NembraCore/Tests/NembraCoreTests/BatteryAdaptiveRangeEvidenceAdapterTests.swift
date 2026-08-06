import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence to adaptive range bridge")
struct BatteryAdaptiveRangeEvidenceAdapterTests {
    private func observation(
        value: BatterySemanticValue,
        role: BatteryEvidenceRole,
        uptime: UInt64 = 100,
        continuity: BatteryEvidenceContinuity = .continuous
    ) throws -> BatteryEvidenceObservation {
        try BatteryEvidenceObservation(
            value: value,
            role: role,
            receivedAtUptimeNanoseconds: uptime,
            receivedAtDate: Date(timeIntervalSince1970: 1_000),
            continuity: continuity
        )
    }

    @Test("verified continuous SoC becomes authoritative adaptive-range evidence")
    func verifiedSOCMapsExactly() throws {
        let source = try observation(
            value: .stateOfChargePercent(73.5),
            role: .verifiedVehicleMeasurement,
            uptime: 42
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .ingestSOC(reading) = action else {
            Issue.record("Expected continuous verified SoC to be ingested")
            return
        }

        #expect(reading.percentage == 73.5)
        #expect(reading.provenance == .authoritativeMeasurement)
        #expect(reading.receivedAtUptimeNanoseconds == 42)
    }

    @Test("all non-verified SoC roles remain outside production range learning")
    func nonVerifiedSOCRolesAreIgnored() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: .stateOfChargePercent(61),
                role: role
            )
            #expect(try BatteryAdaptiveRangeEvidenceAdapter.action(for: source) == .ignore)
        }
    }

    @Test("non-verified continuity markers cannot reset production range learning")
    func nonVerifiedGapMarkersAreIgnored() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: .stateOfChargePercent(60),
                role: role,
                continuity: .afterUnobservedInterval
            )
            #expect(try BatteryAdaptiveRangeEvidenceAdapter.action(for: source) == .ignore)
        }
    }

    @Test("verified non-SoC battery fields never become percentage learning evidence")
    func verifiedElectricalValuesDoNotTrainRange() throws {
        let values: [BatterySemanticValue] = [
            try .voltageVolts(39.8),
            try .currentAmps(-2.5),
            try .powerWatts(98),
            try .chargingState(false)
        ]

        for value in values {
            let source = try observation(
                value: value,
                role: .verifiedVehicleMeasurement
            )
            #expect(try BatteryAdaptiveRangeEvidenceAdapter.action(for: source) == .ignore)
        }
    }

    @Test("verified non-SoC first value after a gap still resets range continuity")
    func verifiedElectricalGapResetsContinuity() throws {
        let source = try observation(
            value: .voltageVolts(40.2),
            role: .verifiedVehicleMeasurement,
            continuity: .afterUnobservedInterval
        )

        #expect(try BatteryAdaptiveRangeEvidenceAdapter.action(for: source) == .resetContinuity)
    }

    @Test("verified SoC after an unobserved interval resets then establishes new evidence")
    func verifiedSOCAfterGapResetsAndIngests() throws {
        let source = try observation(
            value: .stateOfChargePercent(52.25),
            role: .verifiedVehicleMeasurement,
            uptime: 5_000,
            continuity: .afterUnobservedInterval
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .resetContinuityAndIngestSOC(reading) = action else {
            Issue.record("Expected reset plus new verified SoC evidence")
            return
        }

        #expect(reading.percentage == 52.25)
        #expect(reading.provenance == .authoritativeMeasurement)
        #expect(reading.receivedAtUptimeNanoseconds == 5_000)
    }

    @Test("valid empty and full SoC boundaries survive the bridge unchanged")
    func socBoundariesArePreserved() throws {
        for percentage in [0.0, 100.0] {
            let source = try observation(
                value: .stateOfChargePercent(percentage),
                role: .verifiedVehicleMeasurement
            )

            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            guard case let .ingestSOC(reading) = action else {
                Issue.record("Expected boundary SoC to remain eligible")
                continue
            }
            #expect(reading.percentage == percentage)
        }
    }

    @Test("wall clock metadata is not substituted for process-local range ordering")
    func bridgeUsesMonotonicUptimeEvidence() throws {
        let source = try BatteryEvidenceObservation(
            value: .stateOfChargePercent(48),
            role: .verifiedVehicleMeasurement,
            receivedAtUptimeNanoseconds: 9_999,
            receivedAtDate: Date(timeIntervalSince1970: 10),
            continuity: .continuous
        )

        let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
        guard case let .ingestSOC(reading) = action else {
            Issue.record("Expected verified SoC evidence")
            return
        }
        #expect(reading.receivedAtUptimeNanoseconds == 9_999)
    }
}
