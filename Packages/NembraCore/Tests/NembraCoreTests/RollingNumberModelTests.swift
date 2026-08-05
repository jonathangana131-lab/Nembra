import Testing
@testable import NembraCore

@Suite("Rolling instrumentation number model")
struct RollingNumberModelTests {
    private func model(integerDigits: Int = 2, fractionDigits: Int = 0) throws -> RollingNumberModel {
        try RollingNumberModel(
            layout: RollingNumberLayout(
                integerDigits: integerDigits,
                fractionDigits: fractionDigits
            )
        )
    }

    @Test("fixed slots hide leading zeroes without changing layout width")
    func leadingSlotsStayReserved() throws {
        let snapshot = try model(integerDigits: 3).snapshot(for: 7)
        #expect(snapshot.digits.count == 3)
        #expect(snapshot.digits.map(\.digit) == [0, 0, 7])
        #expect(snapshot.digits.map(\.isVisible) == [false, false, true])
    }

    @Test("19 to 20 rolls both affected digits upward through carry")
    func upwardCarry() throws {
        let plan = try model().transition(from: 19, to: 20)
        #expect(plan.direction == .upward)
        #expect(plan.slots[0].fromDigit == 1)
        #expect(plan.slots[0].toDigit == 2)
        #expect(plan.slots[0].direction == .upward)
        #expect(plan.slots[0].rollSteps == 1)
        #expect(plan.slots[1].fromDigit == 9)
        #expect(plan.slots[1].toDigit == 0)
        #expect(plan.slots[1].direction == .upward)
        #expect(plan.slots[1].rollSteps == 1)
    }

    @Test("20 to 19 rolls both affected digits downward through borrow")
    func downwardBorrow() throws {
        let plan = try model().transition(from: 20, to: 19)
        #expect(plan.direction == .downward)
        #expect(plan.slots[0].rollSteps == 1)
        #expect(plan.slots[0].direction == .downward)
        #expect(plan.slots[1].fromDigit == 0)
        #expect(plan.slots[1].toDigit == 9)
        #expect(plan.slots[1].rollSteps == 1)
        #expect(plan.slots[1].direction == .downward)
    }

    @Test("9 to 10 preserves width and marks the tens digit as appearing")
    func leadingDigitAppears() throws {
        let plan = try model().transition(from: 9, to: 10)
        #expect(plan.slots[0].visibilityChange == .appears)
        #expect(plan.slots[0].startsVisible == false)
        #expect(plan.slots[0].endsVisible == true)
        #expect(plan.slots[0].fromDigit == 0)
        #expect(plan.slots[0].toDigit == 1)
        #expect(plan.slots[0].rollSteps == 1)
        #expect(plan.slots[1].fromDigit == 9)
        #expect(plan.slots[1].toDigit == 0)
        #expect(plan.slots[1].rollSteps == 1)
    }

    @Test("10 to 9 marks the tens digit as disappearing downward")
    func leadingDigitDisappears() throws {
        let plan = try model().transition(from: 10, to: 9)
        #expect(plan.slots[0].visibilityChange == .disappears)
        #expect(plan.slots[0].direction == .downward)
        #expect(plan.slots[0].rollSteps == 1)
        #expect(plan.slots[1].direction == .downward)
        #expect(plan.slots[1].rollSteps == 1)
    }

    @Test("99 to 100 carries correctly across three fixed slots")
    func multiDigitCarry() throws {
        let plan = try model(integerDigits: 3).transition(from: 99, to: 100)
        #expect(plan.slots.map(\.rollSteps) == [1, 1, 1])
        #expect(plan.slots.map(\.direction) == [.upward, .upward, .upward])
        #expect(plan.slots[0].visibilityChange == .appears)
    }

    @Test("fractional precision stays fixed and participates in direction")
    func stableFractionDigits() throws {
        let number = try model(integerDigits: 3, fractionDigits: 1)
        let snapshot = try number.snapshot(for: 8.7)
        #expect(snapshot.digits.map(\.digit) == [0, 0, 8, 7])
        #expect(snapshot.digits.map(\.isVisible) == [false, false, true, true])

        let plan = try number.transition(from: 8.7, to: 8.8)
        #expect(plan.direction == .upward)
        #expect(plan.slots.last?.fromDigit == 7)
        #expect(plan.slots.last?.toDigit == 8)
        #expect(plan.slots.last?.rollSteps == 1)
    }

    @Test("equal values have no fake digit motion")
    func equalValueIsStationary() throws {
        let plan = try model().transition(from: 16, to: 16)
        #expect(plan.isStationary)
        #expect(plan.slots.allSatisfy { $0.direction == .stationary && $0.rollSteps == 0 })
    }

    @Test("layouts beyond reliable Double precision are rejected")
    func excessivePrecisionLayoutRejected() {
        #expect(throws: RollingNumberError.invalidLayout) {
            _ = try RollingNumberLayout(integerDigits: 16)
        }
        #expect(throws: RollingNumberError.invalidLayout) {
            _ = try RollingNumberLayout(integerDigits: 8, fractionDigits: 8)
        }
    }

    @Test("invalid values cannot enter the rolling model")
    func invalidValuesRejected() throws {
        let number = try model(integerDigits: 2, fractionDigits: 1)
        #expect(throws: RollingNumberError.negativeValue) {
            _ = try number.snapshot(for: -1)
        }
        #expect(throws: RollingNumberError.nonFiniteValue) {
            _ = try number.snapshot(for: .infinity)
        }
        #expect(throws: RollingNumberError.exceedsLayoutCapacity) {
            _ = try number.snapshot(for: 100)
        }
    }


    @Test("rounding at a decimal carry cannot overflow the declared layout")
    func roundingCapacityGuard() throws {
        let number = try model(integerDigits: 2, fractionDigits: 1)
        let valid = try number.snapshot(for: 99.94)
        #expect(valid.scaledValue == 999)
        #expect(throws: RollingNumberError.exceedsLayoutCapacity) {
            _ = try number.snapshot(for: 99.95)
        }
    }
}
