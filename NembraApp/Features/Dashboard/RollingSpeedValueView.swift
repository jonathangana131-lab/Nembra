import SwiftUI

/// Presentation-only rolling speed digits. The value passed here may be a
/// render interpolation frame; it is never written back into vehicle state.
struct RollingSpeedValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?

    private static let twoDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 2) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    private static let threeDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 3) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    /// Decimal-place IDs are counted from the right so 99 -> 100 preserves the
    /// existing ones/tens views and inserts only the new hundreds column.
    private static let twoDigitPlacesFromRight = [1, 0]
    private static let threeDigitPlacesFromRight = [2, 1, 0]
    private static let maximumThreeDigitDisplayInteger = 999.0

    /// Rendering must not turn malformed speed evidence into a believable
    /// stopped state. Negative and non-finite values remain unavailable, while
    /// signed zero is normalized only for stable presentation.
    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    /// Select presentation capacity using the same integer rounding rule as
    /// `RollingNumberModel`, then let the model validate and build the snapshot.
    /// This avoids a thrown two-digit capacity miss on every three-digit frame.
    private func rollingProjection(
        for value: Double
    ) -> (snapshot: RollingNumberSnapshot, placesFromRight: [Int])? {
        let roundedValue = value.rounded(.toNearestOrAwayFromZero)
        guard roundedValue <= Self.maximumThreeDigitDisplayInteger else { return nil }

        let usesThreeDigits = roundedValue >= 100
        let numberModel = usesThreeDigits
            ? Self.threeDigitNumberModel
            : Self.twoDigitNumberModel
        let placesFromRight = usesThreeDigits
            ? Self.threeDigitPlacesFromRight
            : Self.twoDigitPlacesFromRight

        guard let numberModel,
              let snapshot = try? numberModel.snapshot(for: value) else {
            return nil
        }

        return (snapshot, placesFromRight)
    }

    var body: some View {
        if let value = validatedRenderValue,
           let projection = rollingProjection(for: value) {
            HStack(spacing: -5) {
                ForEach(projection.placesFromRight, id: \.self) { placeFromRight in
                    let index = projection.snapshot.digits.count - 1 - placeFromRight
                    let digit = projection.snapshot.digits[index]

                    Text(String(digit.digit))
                        .opacity(digit.isVisible ? 1 : 0)
                        .contentTransition(
                            reduceMotion ? .identity : .numericText(value: value)
                        )
                }
            }
            // Interpolation timing lives in SpeedInstrumentModel. This brief
            // transition rolls visible integer changes without creating a second
            // speed-smoothing layer. Decimal-place IDs stay stable at 99 -> 100.
            // Reduce Motion keeps the same display value but removes the roll.
            .animation(
                reduceMotion ? nil : .linear(duration: 0.08),
                value: projection.snapshot.scaledValue
            )
        } else {
            Text("—")
        }
    }
}
