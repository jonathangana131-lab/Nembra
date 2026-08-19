import NembraCore
import SwiftUI

/// Presentation-only fixed-slot speed number. Integer and tenths use different
/// visual hierarchy while sharing one package-owned quantization snapshot.
/// Render values never flow back into telemetry or ride evidence.
struct RollingSpeedValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?
    let integerPointSize: CGFloat
    let fractionPointSize: CGFloat

    private static let numberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 2, fractionDigits: 1) else {
            return nil
        }
        return try? RollingNumberModel(layout: layout)
    }()

    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    var body: some View {
        if let value = validatedRenderValue,
           let numberModel = Self.numberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                HStack(spacing: -5) {
                    ForEach(0..<snapshot.layout.integerDigits, id: \.self) { index in
                        rollingDigit(
                            snapshot.digits[index],
                            transitionValue: value,
                            pointSize: integerPointSize,
                            weight: .thin
                        )
                    }
                }

                Text(".")
                    .font(.system(size: fractionPointSize, weight: .regular, design: .rounded))
                    .padding(.horizontal, -2)

                rollingDigit(
                    snapshot.digits[snapshot.layout.integerDigits],
                    transitionValue: value,
                    pointSize: fractionPointSize,
                    weight: .regular
                )
            }
            .monospacedDigit()
        } else {
            Text("—")
                .font(.system(size: integerPointSize * 0.70, weight: .ultraLight, design: .rounded))
                .foregroundStyle(NembraColor.primaryText.opacity(0.60))
                .frame(minWidth: integerPointSize * 0.92, alignment: .center)
        }
    }

    private func rollingDigit(
        _ digit: RollingDigitSnapshot,
        transitionValue: Double,
        pointSize: CGFloat,
        weight: Font.Weight
    ) -> some View {
        Text(String(digit.digit))
            .font(.system(size: pointSize, weight: weight, design: .rounded))
            .opacity(digit.isVisible ? 1 : 0)
            .contentTransition(
                reduceMotion ? .identity : .numericText(value: transitionValue)
            )
            .animation(
                reduceMotion ? nil : .snappy(duration: 0.15),
                value: digit.digit
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: digit.isVisible
            )
            .clipped()
    }
}
