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
            value: BatterySemanticValue.stateOfChargePercent(73.5),
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

    @Test("all non-verified continuous SoC roles remain outside production range learning")
    func nonVerifiedSOCRolesAreIgnored() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: BatterySemanticValue.stateOfChargePercent(61),
                role: role
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .ignore)
        }
    }

    @Test("an explicit continuity gap resets range even when the value is not authoritative")
    func nonVerifiedGapMarkersStillResetContinuity() throws {
        let roles: [BatteryEvidenceRole] = [
            .stockAppCorrelationAnchor,
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let source = try observation(
                value: BatterySemanticValue.stateOfChargePercent(60),
                role: role,
                continuity: .afterUnobservedInterval
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .resetContinuity)
        }
    }

    @Test("verified non-SoC battery fields never become percentage learning evidence")
    func verifiedElectricalValuesDoNotTrainRange() throws {
        let values: [BatterySemanticValue] = [
            try BatterySemanticValue.voltageVolts(39.8),
            try BatterySemanticValue.currentAmps(-2.5),
            try BatterySemanticValue.powerWatts(98),
            try BatterySemanticValue.chargingState(false)
        ]

        for value in values {
            let source = try observation(
                value: value,
                role: .verifiedVehicleMeasurement
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .ignore)
        }
    }

    @Test("every verified non-SoC first value after a gap resets range continuity")
    func verifiedElectricalGapResetsContinuity() throws {
        let values: [BatterySemanticValue] = [
            try BatterySemanticValue.voltageVolts(40.2),
            try BatterySemanticValue.currentAmps(-1.5),
            try BatterySemanticValue.powerWatts(60),
            try BatterySemanticValue.chargingState(true)
        ]

        for value in values {
            let source = try observation(
                value: value,
                role: .verifiedVehicleMeasurement,
                continuity: .afterUnobservedInterval
            )
            let action = try BatteryAdaptiveRangeEvidenceAdapter.action(for: source)
            #expect(action == .resetContinuity)
        }
    }

    @Test("verified non-SoC gap can reset before a later continuous SoC becomes clean evidence")
    func verifiedNonSOCGapThenSOCProducesSeparateActions() throws {
        let firstAfterGap = try observation(
            value: BatterySemanticValue.voltageVolts(40.2),
            role: .verifiedVehicleMeasurement,
            uptime: 4_999,
            continuity: .afterUnobservedInterval
        )
        let laterSOC = try observation(
            value: BatterySemanticValue.stateOfChargePercent(52.25),
            role: .verifiedVehicleMeasurement,
            uptime: 5_000,
            continuity: .continuous
        )

        let resetAction = try BatteryAdaptiveRangeEvidenceAdapter.action(for: firstAfterGap)
        let socAction = try BatteryAdaptiveRangeEvidenceAdapter.action(for: laterSOC)

        #expect(resetAction == .resetContinuity)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected later continuous verified SoC to become clean evidence")
            return
        }
        #expect(reading.percentage == 52.25)
        #expect(reading.receivedAtUptimeNanoseconds == 5_000)
    }

    @Test("verified SoC after an unobserved interval resets then establishes new evidence")
    func verifiedSOCAfterGapResetsAndIngests() throws {
        let source = try observation(
            value: BatterySemanticValue.stateOfChargePercent(52.25),
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
                value: BatterySemanticValue.stateOfChargePercent(percentage),
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
            value: BatterySemanticValue.stateOfChargePercent(48),
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

    @Test("stateful bridge requires an explicit first-post-gap boundary")
    func statefulBridgeFailsClosedWhenBoundaryIsMissing() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        bridge.markUnobservedInterval()

        let source = try observation(
            value: BatterySemanticValue.stateOfChargePercent(51),
            role: .verifiedVehicleMeasurement,
            uptime: 5,
            continuity: .continuous
        )

        #expect(throws: BatteryEvidenceStreamValidationError.missingContinuityBoundary) {
            _ = try bridge.accept(source)
        }
        #expect(bridge.streamValidator.requiresContinuityBoundary)
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == nil)
    }

    @Test("non-authoritative first-post-gap evidence resets learning and starts a fresh stream epoch")
    func nonAuthoritativeBoundaryCannotBeDroppedByStatefulBridge() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        bridge.markUnobservedInterval()

        let boundary = try observation(
            value: BatterySemanticValue.stateOfChargePercent(60),
            role: .stockAppCorrelationAnchor,
            uptime: 4,
            continuity: .afterUnobservedInterval
        )
        let laterVerifiedSOC = try observation(
            value: BatterySemanticValue.stateOfChargePercent(59),
            role: .verifiedVehicleMeasurement,
            uptime: 5,
            continuity: .continuous
        )

        let boundaryAction = try bridge.accept(boundary)
        let socAction = try bridge.accept(laterVerifiedSOC)

        #expect(boundaryAction == .resetContinuity)
        #expect(bridge.streamValidator.requiresContinuityBoundary == false)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected later verified SoC to enter the fresh epoch")
            return
        }
        #expect(reading.percentage == 59)
    }

    @Test("stateful bridge rejects uptime regression atomically before range ingest")
    func statefulBridgeRejectsUptimeRegressionAtomically() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        let first = try observation(
            value: BatterySemanticValue.stateOfChargePercent(70),
            role: .verifiedVehicleMeasurement,
            uptime: 100
        )
        let regressed = try observation(
            value: BatterySemanticValue.stateOfChargePercent(69),
            role: .verifiedVehicleMeasurement,
            uptime: 99
        )

        _ = try bridge.accept(first)
        #expect(throws: BatteryEvidenceStreamValidationError.nonMonotonicUptime) {
            _ = try bridge.accept(regressed)
        }
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == 100)
    }

    @Test("equal uptime battery fields from one callback remain valid and only SoC is ingested")
    func statefulBridgeAllowsEqualUptimeFields() throws {
        var bridge = BatteryAdaptiveRangeEvidenceBridge()
        let voltage = try observation(
            value: BatterySemanticValue.voltageVolts(40.0),
            role: .verifiedVehicleMeasurement,
            uptime: 200
        )
        let soc = try observation(
            value: BatterySemanticValue.stateOfChargePercent(68),
            role: .verifiedVehicleMeasurement,
            uptime: 200
        )

        let voltageAction = try bridge.accept(voltage)
        let socAction = try bridge.accept(soc)

        #expect(voltageAction == .ignore)
        guard case let .ingestSOC(reading) = socAction else {
            Issue.record("Expected same-callback SoC to remain eligible")
            return
        }
        #expect(reading.percentage == 68)
        #expect(bridge.streamValidator.lastAcceptedUptimeNanoseconds == 200)
    }
}
