import Foundation
import Testing
@testable import NembraCore

struct BatteryObservationTruthTests {
    @Test
    func unclassifiedNumberCannotBecomeBatteryObservation() {
        let observation = AuthoritativeBatteryObservation(
            percent: 73,
            authority: nil,
            observedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(observation == nil)
    }

    @Test
    func everyExplicitAuthorityRemainsDistinct() throws {
        let date = Date(timeIntervalSince1970: 2_000)

        for authority in BatteryObservationAuthority.allCases {
            let observation = try #require(
                AuthoritativeBatteryObservation(
                    percent: 51,
                    authority: authority,
                    observedAt: date
                )
            )

            #expect(observation.percent == 51)
            #expect(observation.authority == authority)
            #expect(observation.observedAt == date)
        }
    }

    @Test
    func retentionDoesNotUpgradeEstimateIntoMeasurement() throws {
        let observedAt = Date(timeIntervalSince1970: 3_000)
        let retainedAt = Date(timeIntervalSince1970: 3_600)
        let observation = try #require(
            AuthoritativeBatteryObservation(
                percent: 42,
                authority: .estimated,
                observedAt: observedAt
            )
        )
        let snapshot = try #require(observation.retained(at: retainedAt))

        #expect(snapshot.percent == 42)
        #expect(snapshot.authority == .estimated)
        #expect(snapshot.observedAt == observedAt)
        #expect(snapshot.retainedAt == retainedAt)
    }

    @Test
    func invalidPercentAndNonFiniteTimeFailClosed() {
        #expect(
            AuthoritativeBatteryObservation(
                percent: -1,
                authority: .measured,
                observedAt: Date(timeIntervalSince1970: 4_000)
            ) == nil
        )
        #expect(
            AuthoritativeBatteryObservation(
                percent: 101,
                authority: .displayOnly,
                observedAt: Date(timeIntervalSince1970: 4_000)
            ) == nil
        )
        #expect(
            AuthoritativeBatteryObservation(
                percent: 50,
                authority: .measured,
                observedAt: Date(timeIntervalSince1970: .infinity)
            ) == nil
        )
    }
}
