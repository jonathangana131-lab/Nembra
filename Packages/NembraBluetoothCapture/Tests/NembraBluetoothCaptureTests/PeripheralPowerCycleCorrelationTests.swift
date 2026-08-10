import Foundation
import Testing
@testable import NembraBluetoothCapture

@Suite("Peripheral power-cycle correlation")
struct PeripheralPowerCycleCorrelationTests {
    private let target = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let other = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let background = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    @Test("same full peripheral UUID must appear uniquely in both OFF to ON transitions")
    func repeatedUniqueTargetCorrelates() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background, target],
            off2: [background],
            on2: [background, target]
        )
        #expect(result == .correlated(target))
    }

    @Test("peripherals already present while OFF cannot become target authority")
    func persistentBackgroundIsIgnored() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background, other],
            on1: [background, other, target],
            off2: [background, other],
            on2: [background, other, target]
        )
        #expect(result == .correlated(target))
    }

    @Test("missing first appearance fails closed")
    func firstTransitionMissingFailsClosed() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background],
            off2: [background],
            on2: [background, target]
        )
        #expect(result == .missingFirst)
    }

    @Test("ambiguous first appearance fails closed with exact candidates")
    func firstTransitionAmbiguousFailsClosed() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background, target, other],
            off2: [background],
            on2: [background, target]
        )
        #expect(result == .ambiguousFirst(candidates: [target, other]))
    }

    @Test("missing second appearance fails closed")
    func secondTransitionMissingFailsClosed() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background, target],
            off2: [background],
            on2: [background]
        )
        #expect(result == .missingSecond)
    }

    @Test("ambiguous second appearance fails closed with exact candidates")
    func secondTransitionAmbiguousFailsClosed() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background, target],
            off2: [background],
            on2: [background, target, other]
        )
        #expect(result == .ambiguousSecond(candidates: [target, other]))
    }

    @Test("different unique UUIDs across repeats never correlate")
    func repeatMismatchFailsClosed() {
        let result = PeripheralPowerCycleCorrelation.resolveRepeated(
            off1: [background],
            on1: [background, target],
            off2: [background],
            on2: [background, other]
        )
        #expect(result == .mismatch(first: target, second: other))
    }

    @Test("empty observations cannot manufacture a target")
    func emptyObservationsFailClosed() {
        #expect(
            PeripheralPowerCycleCorrelation.resolveRepeated(
                off1: [], on1: [], off2: [], on2: []
            ) == .missingFirst
        )
    }
}
