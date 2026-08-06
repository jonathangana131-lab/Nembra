import Foundation
import Testing
@testable import NembraCore

@Suite("Battery electrical coherence")
struct BatteryElectricalCoherenceTests {
    private func observation(
        field: BatteryEvidenceField,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        uptime: UInt64,
        numericValue: Double
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
            receivedAtDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )
    }

    private func truthSnapshot(
        voltage: BatteryEvidenceLiveTruthState = .unavailable,
        current: BatteryEvidenceLiveTruthState = .unavailable,
        power: BatteryEvidenceLiveTruthState = .unavailable
    ) -> BatteryEvidenceLiveTruthSnapshot {
        BatteryEvidenceLiveTruthSnapshot(
            stateByField: [
                .voltageVolts: voltage,
                .currentAmps: current,
                .powerWatts: power
            ]
        )
    }

    @Test("no verified-live voltage or current is unavailable")
    func missingPairIsUnavailable() {
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state == .unavailable)
        #expect(!state.isCoherentPair)
    }

    @Test("verified-live voltage alone remains partial")
    func voltageOnlyIsPartial() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 10, numericValue: 40.1)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(voltage: .verifiedLive(voltage, ageNanoseconds: 1)),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state == .voltageOnly(voltage))
        #expect(!state.isCoherentPair)
    }

    @Test("verified-live current alone remains partial")
    func currentOnlyIsPartial() throws {
        let current = try observation(field: .currentAmps, uptime: 10, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(current: .verifiedLive(current, ageNanoseconds: 1)),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state == .currentOnly(current))
        #expect(!state.isCoherentPair)
    }

    @Test("zero skew policy accepts only exact same-uptime pair")
    func exactSameUptimeCanBeCoherent() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 20, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 20, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .verifiedLive(voltage, ageNanoseconds: 1),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(
            state == .coherent(
                voltage: voltage,
                current: current,
                skewNanoseconds: 0
            )
        )
        #expect(state.isCoherentPair)
    }

    @Test("pair inside injected skew is coherent")
    func pairInsideInjectedSkewIsCoherent() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 100, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 106, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .verifiedLive(voltage, ageNanoseconds: 7),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 6)
        )

        #expect(
            state == .coherent(
                voltage: voltage,
                current: current,
                skewNanoseconds: 6
            )
        )
    }

    @Test("pair beyond injected skew stays explicitly incoherent")
    func pairOutsideInjectedSkewIsIncoherent() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 100, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 107, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .verifiedLive(voltage, ageNanoseconds: 8),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 6)
        )

        #expect(
            state == .incoherent(
                voltage: voltage,
                current: current,
                skewNanoseconds: 7
            )
        )
        #expect(!state.isCoherentPair)
    }

    @Test("skew calculation is symmetric when voltage is newer")
    func skewIsSymmetric() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 108, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 100, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .verifiedLive(voltage, ageNanoseconds: 1),
                current: .verifiedLive(current, ageNanoseconds: 9)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 8)
        )

        #expect(
            state == .coherent(
                voltage: voltage,
                current: current,
                skewNanoseconds: 8
            )
        )
    }

    @Test("stale verified voltage is not pairable as live")
    func staleVerifiedEvidenceIsExcluded() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 100, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 100, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .stale(voltage, ageNanoseconds: 100),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 100)
        )

        #expect(state == .currentOnly(current))
    }

    @Test("fresh nonauthoritative voltage is not pairable as verified electrical truth")
    func nonAuthoritativeEvidenceIsExcluded() throws {
        let voltage = try observation(
            field: .voltageVolts,
            role: .stockAppCorrelationAnchor,
            uptime: 100,
            numericValue: 40.1
        )
        let current = try observation(field: .currentAmps, uptime: 100, numericValue: 3.2)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .freshNonAuthoritative(voltage, ageNanoseconds: 1),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state == .currentOnly(current))
    }

    @Test("verified-live power never substitutes for missing voltage or current")
    func powerDoesNotSubstituteForPair() throws {
        let power = try observation(field: .powerWatts, uptime: 100, numericValue: 128)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(power: .verifiedLive(power, ageNanoseconds: 1)),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state == .unavailable)
    }

    @Test("signed verified current is preserved without reinterpretation")
    func signedCurrentIsPreserved() throws {
        let voltage = try observation(field: .voltageVolts, uptime: 100, numericValue: 40.1)
        let current = try observation(field: .currentAmps, uptime: 100, numericValue: -2.5)
        let state = BatteryVerifiedElectricalPairEvaluator.evaluate(
            truthSnapshot(
                voltage: .verifiedLive(voltage, ageNanoseconds: 1),
                current: .verifiedLive(current, ageNanoseconds: 1)
            ),
            policy: BatteryElectricalCoherencePolicy(maximumVoltageCurrentSkewNanoseconds: 0)
        )

        #expect(state.isCoherentPair)
        #expect(current.value.numericValue == -2.5)
    }
}
