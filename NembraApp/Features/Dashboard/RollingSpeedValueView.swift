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

    var body: some View {
        if let value,
           let numberModel = Self.numberModel,
           let snapshot = try? numberModel.snapshot(for: max(0, value)) {
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
        } else if let value {
            Text(String(format: "%.0f", max(0, value)))
                .contentTransition(
                    reduceMotion ? .identity : .numericText(value: value)
                )
        } else {
            Text("—")
        }
    }
}
