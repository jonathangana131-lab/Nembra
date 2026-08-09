import SwiftUI

/// Presentation-only rolling speed digits. The value passed here may be a
/// render interpolation frame; it is never written back into vehicle state.
struct RollingSpeedValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?

    private static let numberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 2) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    /// The compact non-rolling fallback can faithfully lay out three integer
    /// digits. This is a presentation capacity, not a physical scooter-speed
    /// limit; values requiring more space fail closed rather than being clamped.
    private static let maximumFallbackDisplayInteger = 999.0

    /// Rendering must not turn malformed speed evidence into a believable
    /// stopped state. Negative and non-finite values remain unavailable, while
    /// signed zero is normalized only for stable presentation.
    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    /// Keep fallback rounding identical to `RollingNumberModel` so the handoff
    /// at the two-digit rolling capacity is deterministic. Conversion happens
    /// only after the rounded value is proven representable, so extreme finite
    /// `Double` values can never expand into unbounded cockpit text.
    private var boundedFallbackText: String? {
        guard let value = validatedRenderValue else { return nil }
        let roundedValue = value.rounded(.toNearestOrAwayFromZero)
        guard roundedValue <= Self.maximumFallbackDisplayInteger else { return nil }
        return String(Int(roundedValue))
    }

    var body: some View {
        if let value = validatedRenderValue {
            if let numberModel = Self.numberModel,
               let snapshot = try? numberModel.snapshot(for: value) {
                HStack(spacing: -5) {
                    ForEach(snapshot.digits.indices, id: \.self) { index in
                        rollingDigit(
                            snapshot.digits[index],
                            transitionValue: value
                        )
                    }
                }
            } else if let fallbackText = boundedFallbackText {
                Text(fallbackText)
                    .contentTransition(
                        reduceMotion ? .identity : .numericText(value: value)
                    )
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.10),
                        value: fallbackText
                    )
            } else {
                Text("—")
            }
        } else {
            Text("—")
        }
    }

    /// Each fixed digit slot owns its own brief roll so an unchanged column does
    /// not inherit animation work just because another digit changed. The whole
    /// render value remains the numeric-transition direction signal: on an
    /// increasing boundary such as 19 -> 20, the ones column must roll forward
    /// through 9 -> 0 rather than visually count down merely because its local
    /// glyph value decreased.
    ///
    /// The clip keeps native numeric-transition travel inside the digit's stable
    /// glyph bounds. These frames are display-only and never feed vehicle truth.
    @ViewBuilder
    private func rollingDigit(
        _ digit: RollingDigitSnapshot,
        transitionValue: Double
    ) -> some View {
        Text(String(digit.digit))
            .opacity(digit.isVisible ? 1 : 0)
            .contentTransition(
                reduceMotion ? .identity : .numericText(value: transitionValue)
            )
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.10),
                value: digit.digit
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: digit.isVisible
            )
            .clipped()
    }
}