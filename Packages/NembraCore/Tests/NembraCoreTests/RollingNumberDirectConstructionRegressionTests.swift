import Testing
@testable import NembraCore

@Suite("Rolling snapshot direct construction regressions")
struct RollingNumberDirectConstructionRegressionTests {
    @Test("every two-digit cockpit value preserves slot ordering and visibility")
    func everyTwoDigitCockpitValuePreservesShape() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2)
        )

        for value in 0...99 {
            let snapshot = try model.snapshot(for: Double(value))

            #expect(snapshot.scaledValue == UInt64(value))
            #expect(snapshot.digits.count == 2)
            #expect(snapshot.digits[0].digit == value / 10)
            #expect(snapshot.digits[1].digit == value % 10)
            #expect(snapshot.digits[0].isVisible == (value >= 10))
            #expect(snapshot.digits[1].isVisible)
        }
    }

    @Test("maximum supported fixed layout preserves most-to-least-significant ordering")
    func maximumSupportedLayoutPreservesOrdering() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 15)
        )
        let snapshot = try model.snapshot(for: 123_456_789_012_345)

        #expect(snapshot.scaledValue == 123_456_789_012_345)
        #expect(snapshot.digits.map(\.digit) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 1, 2, 3, 4, 5])
        #expect(snapshot.digits.allSatisfy { $0.isVisible })
    }

    @Test("fractional slots remain visible while leading integer slots stay reserved")
    func fractionalVisibilityRemainsStable() throws {
        let model = try RollingNumberModel(
            layout: RollingNumberLayout(integerDigits: 2, fractionDigits: 2)
        )
        let snapshot = try model.snapshot(for: 0.07)

        #expect(snapshot.scaledValue == 7)
        #expect(snapshot.digits.map(\.digit) == [0, 0, 0, 7])
        #expect(snapshot.digits.map(\.isVisible) == [false, true, true, true])
    }
}