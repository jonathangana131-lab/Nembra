import SwiftUI

/// Presentation-only rolling speed digits. The value passed here may be a
/// render interpolation frame; it is never written back into vehicle state.
struct RollingSpeedValueView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Double?

    /// Preserve the established compact geometry for normal scooter speeds while
    /// keeping a second rolling layout available when the rounded display crosses
    /// into three digits. Switching layout at that semantic boundary is preferable
    /// to dropping the signature instrument into a monolithic fallback `Text`.
    private static let twoDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 2) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    private static let threeDigitNumberModel: RollingNumberModel? = {
        guard let layout = try? RollingNumberLayout(integerDigits: 3) else { return nil }
        return try? RollingNumberModel(layout: layout)
    }()

    /// Stable semantic IDs measured from the least-significant integer place.
    /// At 99 -> 100, ones stays `0`, tens stays `1`, and only hundreds `2`
    /// appears. SwiftUI therefore never reuses a tens/ones view as a different
    /// decimal place merely because the layout gained one leading digit.
    private static let twoDigitPlacesFromRight = [1, 0]
    private static let threeDigitPlacesFromRight = [2, 1, 0]

    /// Rendering must not turn malformed speed evidence into a believable
    /// stopped state. Negative and non-finite values remain unavailable, while
    /// signed zero is normalized only for stable presentation.
    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    /// Let `RollingNumberModel` remain the single rounding/capacity contract.
    /// Normal 0...99 presentation stays on the existing compact layout; only a
    /// value that cannot be represented there falls through to the three-digit
    /// rolling layout. Values beyond that layout still fail closed.
    private func rollingSnapshot(for value: Double) -> RollingNumberSnapshot? {
        if let numberModel = Self.twoDigitNumberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            return snapshot
        }

        if let numberModel = Self.threeDigitNumberModel,
           let snapshot = try? numberModel.snapshot(for: value) {
            return snapshot
        }

        return nil
    }

    private func placesFromRight(for snapshot: RollingNumberSnapshot) -> [Int] {
        switch snapshot.layout.integerDigits {
        case 2:
            return Self.twoDigitPlacesFromRight
        case 3:
            return Self.threeDigitPlacesFromRight
        default:
            return []
        }
    }

    var body: some View {
        if let value = validatedRenderValue,
           let snapshot = rollingSnapshot(for: value) {
            let placesFromRight = placesFromRight(for: snapshot)

            HStack(spacing: -5) {
                ForEach(placesFromRight, id: \.self) { placeFromRight in
                    let index = snapshot.digits.count - 1 - placeFromRight
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
            // Decimal-place IDs remain stable when the leading hundreds slot
            // appears/disappears, and newer frames retarget immediately.
            // Reduce Motion keeps the same display value but removes the roll.
            .animation(
                reduceMotion ? nil : .linear(duration: 0.08),
                value: snapshot.scaledValue
            )
        } else {
            Text("—")
        }
    }
}
