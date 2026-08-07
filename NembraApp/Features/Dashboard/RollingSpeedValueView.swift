import Foundation
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

    /// Rendering must not turn malformed speed evidence into a believable
    /// stopped state. Negative and non-finite values remain unavailable, while
    /// signed zero is normalized only for stable presentation.
    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
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
            } else {
                Text(String(format: "%.0f", locale: Locale.current, value))
                    .contentTransition(
                        reduceMotion ? .identity : .numericText(value: value)
                    )
            }
        } else {
            Text("—")
        }
    }
}
