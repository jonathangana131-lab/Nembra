import Testing
@testable import NembraCore

@Suite("Rolling instrumentation performance hardening")
struct RollingNumberPerformanceHardeningTests {
    @Test("exact scaled snapshots match Double quantization")
    func exactScaledSnapshotMatchesDoublePath() throws {
        let layout = try RollingNumberLayout(integerDigits: 3, fractionDigits: 1)
        let model = try RollingNumberModel(layout: layout)

        let fromDouble = try model.snapshot(for: 8.7)
        let fromScaledValue = try model.snapshot(scaledValue: 87)

        #expect(fromScaledValue == fromDouble)
        #expect(fromScaledValue.digits.map(\.digit) == [0, 0, 8, 7])
        #expect(fromScaledValue.digits.map(\.isVisible) == [false, false, true, true])
    }

    @Test("exact scaled path enforces layout capacity")
    func exactScaledPathCapacityGuard() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2)
        )

        #expect(try model.snapshot(scaledValue: 99).scaledValue == 99)
        #expect(throws: RollingNumberError.exceedsLayoutCapacity) {
            _ = try model.snapshot(scaledValue: 100)
        }
    }

    @Test("largest supported layout constructs directly without intermediate precision loss")
    func largestSupportedLayout() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 15)
        )
        let maximum: UInt64 = 999_999_999_999_999
        let snapshot = try model.snapshot(scaledValue: maximum)

        #expect(snapshot.scaledValue == maximum)
        #expect(snapshot.digits.count == 15)
        #expect(snapshot.digits.allSatisfy { $0.digit == 9 && $0.isVisible })
    }

    @Test("all two-digit snapshots preserve fixed slot shape")
    func allTwoDigitSnapshotsPreserveShape() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2)
        )

        for value in UInt64(0)...99 {
            let snapshot = try model.snapshot(scaledValue: value)
            #expect(snapshot.scaledValue == value)
            #expect(snapshot.digits.count == 2)
            #expect(snapshot.digits.last?.isVisible == true)
            if value < 10 {
                #expect(snapshot.digits.first?.isVisible == false)
            } else {
                #expect(snapshot.digits.first?.isVisible == true)
            }
        }
    }

    @Test("transition work remains bounded to fixed slots even across a large jump")
    func largeJumpTransitionIsSlotBounded() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2)
        )
        let plan = try model.transition(from: 0, to: 99)

        #expect(plan.direction == .upward)
        #expect(plan.slots.count == 2)
        #expect(plan.slots.map(\.slotIndex) == [0, 1])
        #expect(plan.slots.allSatisfy { (0...9).contains($0.rollSteps) })
        #expect(plan.slots.map(\.rollSteps) == [9, 9])
    }

    @Test("fraction slots stay visible on the exact integer path")
    func fractionalSlotsStayVisible() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2, fractionDigits: 2)
        )
        let snapshot = try model.snapshot(scaledValue: 7)

        #expect(snapshot.digits.map(\.digit) == [0, 0, 0, 7])
        #expect(snapshot.digits.map(\.isVisible) == [false, true, true, true])
    }
}
