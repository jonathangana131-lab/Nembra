import Foundation
import NembraCore
import SwiftUI

/// Presentation-only fixed-slot speed number. Integer and tenths use different
/// visual hierarchy while sharing one package-owned quantization snapshot.
/// Render values never flow back into telemetry or ride evidence.
struct RollingSpeedValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale

    let value: Double?
    let integerPointSize: CGFloat
    let fractionPointSize: CGFloat

    private static let twoDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 2, fractionDigits: 1) else {
            return nil
        }
        return try? RollingNumberModel(layout: layout)
    }()

    private static let threeDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 3, fractionDigits: 1) else {
            return nil
        }
        return try? RollingNumberModel(layout: layout)
    }()

    static func supports(_ value: Double?) -> Bool {
        guard let value, value.isFinite, value >= 0, value < 999.95 else { return false }
        return true
    }

    static func decimalSeparator(for locale: Locale) -> String {
        locale.decimalSeparator ?? "."
    }

    private var validatedRenderValue: Double? {
        guard Self.supports(value), let value else { return nil }
        return value == 0 ? 0 : value
    }

    var body: some View {
        if let value = validatedRenderValue,
           let numberModel = value < 99.95
                ? Self.twoDigitNumberModel
                : Self.threeDigitNumberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            let resolvedIntegerPointSize = snapshot.layout.integerDigits == 3
                ? integerPointSize * 0.80
                : integerPointSize
            let visibleDigitKey = snapshot.digits.map(\.digit)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                HStack(spacing: -7) {
                    ForEach(0..<snapshot.layout.integerDigits, id: \.self) { index in
                        rollingDigit(
                            snapshot.digits[index],
                            transitionValue: value,
                            pointSize: resolvedIntegerPointSize,
                            weight: .ultraLight
                        )
                    }
                }

                Text(Self.decimalSeparator(for: locale))
                    .font(.system(size: fractionPointSize, weight: .light, design: .default))
                    .fontWidth(.expanded)
                    .padding(.horizontal, -2)

                rollingDigit(
                    snapshot.digits[snapshot.layout.integerDigits],
                    transitionValue: value,
                    pointSize: fractionPointSize,
                    weight: .light
                )
            }
            .monospacedDigit()
            .animation(
                reduceMotion ? nil : .smooth(duration: 0.16),
                value: visibleDigitKey
            )
        } else {
            Text("—")
                .font(.system(size: integerPointSize * 0.70, weight: .ultraLight, design: .default))
                .fontWidth(.expanded)
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
            .font(.system(size: pointSize, weight: weight, design: .default))
            .fontWidth(.expanded)
            .opacity(digit.isVisible ? 1 : 0)
            .contentTransition(
                reduceMotion ? .identity : .numericText(value: transitionValue)
            )
            .clipped()
    }
}
