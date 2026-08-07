import Foundation
import Testing
@testable import NembraCore

@Suite("Battery evidence live truth")
struct BatteryEvidenceLiveTruthTests {
    private func observation(
        field: BatteryEvidenceField = .stateOfChargePercent,
        role: BatteryEvidenceRole = .verifiedVehicleMeasurement,
        uptime: UInt64 = 100,
        numericValue: Double = 50
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

    @Test("unavailable remains unavailable")
    func unavailableStaysUnavailable() {
        let state = BatteryEvidenceLiveTruthResolver.resolve(.unavailable)
        #expect(state == .unavailable)
        #expect(state.observation == nil)
        #expect(!state.isVerifiedLive)
    }

    @Test("verified evidence with unknown freshness cannot become live")
    func unclassifiedFreshnessIsNotLive() throws {
        let evidence = try observation()
        let state = BatteryEvidenceLiveTruthResolver.resolve(.unclassified(evidence))

        #expect(state == .freshnessUnclassified(evidence))
        #expect(state.observation == evidence)
        #expect(state.verifiedLiveObservation == nil)
    }

    @Test("stale verified evidence remains retained but is not live")
    func staleVerifiedEvidenceIsNotLive() throws {
        let evidence = try observation(field: .voltageVolts, numericValue: 40.1)
        let state = BatteryEvidenceLiveTruthResolver.resolve(
            .stale(evidence, ageNanoseconds: 11)
        )

        #expect(state == .stale(evidence, ageNanoseconds: 11))
        #expect(state.observation == evidence)
        #expect(!state.isVerifiedLive)
    }

    @Test("fresh verified measurement becomes verified live")
    func freshVerifiedEvidenceBecomesLive() throws {
        let evidence = try observation(field: .voltageVolts, numericValue: 40.1)
        let state = BatteryEvidenceLiveTruthResolver.resolve(
            .fresh(evidence, ageNanoseconds: 4)
        )

        #expect(state == .verifiedLive(evidence, ageNanoseconds: 4))
        #expect(state.verifiedLiveObservation == evidence)
        #expect(state.isVerifiedLive)
    }

    @Test("fresh stock-app correlation evidence is not authoritative live truth")
    func freshStockAppEvidenceIsNonAuthoritative() throws {
        let evidence = try observation(
            field: .voltageVolts,
            role: .stockAppCorrelationAnchor,
            numericValue: 40.1
        )
        let state = BatteryEvidenceLiveTruthResolver.resolve(
            .fresh(evidence, ageNanoseconds: 1)
        )

        #expect(state == .freshNonAuthoritative(evidence, ageNanoseconds: 1))
        #expect(state.observation?.role == .stockAppCorrelationAnchor)
        #expect(!state.isVerifiedLive)
    }

    @Test("fresh simulation estimate and presentation roles stay nonauthoritative")
    func allNonAuthoritativeFreshRolesStayNonLive() throws {
        let roles: [BatteryEvidenceRole] = [
            .simulationFixture,
            .derivedEstimate,
            .presentationOnly
        ]

        for role in roles {
            let evidence = try observation(role: role)
            let state = BatteryEvidenceLiveTruthResolver.resolve(
                .fresh(evidence, ageNanoseconds: 0)
            )

            #expect(state == .freshNonAuthoritative(evidence, ageNanoseconds: 0))
            #expect(!state.isVerifiedLive)
        }
    }

    @Test("mixed availability snapshot resolves each field independently")
    func snapshotPreservesIndependentTruthStates() throws {
        let soc = try observation(field: .stateOfChargePercent, numericValue: 72)
        let voltage = try observation(field: .voltageVolts, numericValue: 40.2)
        let current = try observation(
            field: .currentAmps,
            role: .stockAppCorrelationAnchor,
            numericValue: 3.1
        )
        let power = try observation(field: .powerWatts, numericValue: 140)

        let availability = BatteryEvidenceAvailabilitySnapshot(
            availabilityByField: [
                .stateOfChargePercent: .fresh(soc, ageNanoseconds: 2),
                .voltageVolts: .stale(voltage, ageNanoseconds: 50),
                .currentAmps: .fresh(current, ageNanoseconds: 1),
                .powerWatts: .unclassified(power),
                .chargingState: .unavailable
            ]
        )

        let truth = BatteryEvidenceLiveTruthResolver.resolve(availability)

        #expect(truth[.stateOfChargePercent] == .verifiedLive(soc, ageNanoseconds: 2))
        #expect(truth[.voltageVolts] == .stale(voltage, ageNanoseconds: 50))
        #expect(truth[.currentAmps] == .freshNonAuthoritative(current, ageNanoseconds: 1))
        #expect(truth[.powerWatts] == .freshnessUnclassified(power))
        #expect(truth[.chargingState] == .unavailable)
    }

    @Test("verified-live helper returns only fresh authoritative fields")
    func helperNeverReturnsStaleOrUnverifiedEvidence() throws {
        let soc = try observation(field: .stateOfChargePercent, numericValue: 72)
        let voltage = try observation(field: .voltageVolts, numericValue: 40.2)
        let current = try observation(
            field: .currentAmps,
            role: .simulationFixture,
            numericValue: 3.1
        )

        let truth = BatteryEvidenceLiveTruthSnapshot(
            stateByField: [
                .stateOfChargePercent: .verifiedLive(soc, ageNanoseconds: 1),
                .voltageVolts: .stale(voltage, ageNanoseconds: 20),
                .currentAmps: .freshNonAuthoritative(current, ageNanoseconds: 1)
            ]
        )

        #expect(truth.verifiedLiveObservation(for: .stateOfChargePercent) == soc)
        #expect(truth.verifiedLiveObservation(for: .voltageVolts) == nil)
        #expect(truth.verifiedLiveObservation(for: .currentAmps) == nil)
        #expect(truth.verifiedLiveObservation(for: .powerWatts) == nil)
    }
}
