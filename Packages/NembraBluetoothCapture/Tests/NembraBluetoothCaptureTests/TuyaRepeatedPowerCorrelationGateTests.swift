import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Tuya repeated power correlation gate")
struct TuyaRepeatedPowerCorrelationGateTests {
    private let scooter = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let historical = UUID(uuidString: "6815A5F5-4D1E-E004-BAE8-6DF924123907")!
    private let neighbor = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let ambient = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    @Test("one peripheral present in both ON observations and neither OFF observation correlates")
    func uniqueRepeatedPowerOnOnlyCandidateCorrelates() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, scooter],
            off2: [ambient],
            on2: [ambient, scooter]
        ))

        #expect(verdict == .correlated(peripheralID: scooter))
    }

    @Test("a peripheral seen during either OFF observation cannot correlate")
    func anyOffObservationDisqualifiesCandidate() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, scooter],
            off2: [ambient, scooter],
            on2: [ambient, scooter]
        ))

        #expect(verdict == .blocked(.noRepeatablePowerOnOnlyCandidate))
    }

    @Test("a one-cycle appearance cannot earn repeated correlation")
    func onePowerOnCycleIsInsufficient() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, scooter],
            off2: [ambient],
            on2: [ambient]
        ))

        #expect(verdict == .blocked(.noRepeatablePowerOnOnlyCandidate))
    }

    @Test("multiple repeatable candidates fail closed without a hint-based tie breaker")
    func ambiguityFailsClosedDeterministically() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, scooter, neighbor],
            off2: [ambient],
            on2: [ambient, scooter, neighbor]
        ))

        #expect(verdict == .blocked(.ambiguousRepeatablePowerOnOnlyCandidates([scooter, neighbor])))
    }

    @Test("historical C7D09A22 UUID receives no authority when it does not satisfy the current sequence")
    func historicalPeripheralHasNoSpecialAuthority() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, historical, scooter],
            off2: [ambient],
            on2: [ambient, scooter]
        ))

        #expect(verdict == .correlated(peripheralID: scooter))
    }

    @Test("historical UUID may correlate only by satisfying the same current four-observation rule")
    func historicalPeripheralMustEarnCurrentCorrelationNormally() {
        let verdict = TuyaRepeatedPowerCorrelationGate.verdict(for: .init(
            off1: [ambient],
            on1: [ambient, historical],
            off2: [ambient],
            on2: [ambient, historical]
        ))

        #expect(verdict == .correlated(peripheralID: historical))
    }
}
