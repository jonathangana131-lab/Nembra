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
                        let digit = snapshot.digits[index]
                        Text(String(digit.digit))
                            .opacity(digit.isVisible ? 1 : 0)
                            .contentTransition(
                                reduceMotion ? .identity : .numericText(value: value)
                            )
                    }
                }
                // Interpolation timing lives in SpeedInstrumentModel. This brief
                // transition only rolls a visible integer when the rendered value
                // crosses that integer; it is not a second speed-smoothing layer.
                // Reduce Motion keeps the same display value but removes the roll.
                .animation(
                    reduceMotion ? nil : .linear(duration: 0.08),
                    value: snapshot.scaledValue
                )
            } else if let fallbackText = boundedFallbackText {
                Text(fallbackText)
                    .contentTransition(
                        reduceMotion ? .identity : .numericText(value: value)
                    )
            } else {
                Text("—")
            }
        } else {
            Text("—")
        }
    }
}
