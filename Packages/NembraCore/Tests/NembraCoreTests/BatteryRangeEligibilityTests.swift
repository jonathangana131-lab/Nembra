import Foundation
import Testing
@testable import NembraCore

@Suite("Battery range eligibility")
struct BatteryRangeEligibilityTests {
    @Test("live measured battery can cross the current-range boundary")
    func liveMeasuredIsEligible() throws {
        let observedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let observation = try #require(AuthoritativeBatteryObservation(
            percent: 64,
            authority: .measured,
            observedAt: observedAt
        ))

        let eligible = observation.rangeEligible(currentness: .live)

        #expect(eligible?.percent == 64)
        #expect(eligible?.observedAt == observedAt)
    }

    @Test("retained measured battery stays historical and cannot drive current remaining range")
    func retainedMeasuredIsNotCurrentRangeEvidence() throws {
        let observation = try #require(AuthoritativeBatteryObservation(
            percent: 64,
            authority: .measured,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        #expect(observation.physicalMeasurement != nil)
        #expect(observation.rangeEligible(currentness: .retained) == nil)
    }

    @Test("live estimated battery cannot become physical range evidence")
    func liveEstimatedIsNotRangeEvidence() throws {
        let observation = try #require(AuthoritativeBatteryObservation(
            percent: 52,
            authority: .estimated,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        #expect(observation.physicalMeasurement == nil)
        #expect(observation.rangeEligible(currentness: .live) == nil)
    }

    @Test("live display-only battery cannot become physical range evidence")
    func liveDisplayOnlyIsNotRangeEvidence() throws {
        let observation = try #require(AuthoritativeBatteryObservation(
            percent: 41,
            authority: .displayOnly,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        #expect(observation.physicalMeasurement == nil)
        #expect(observation.rangeEligible(currentness: .live) == nil)
    }
}
