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

    /// Rendering must not turn malformed speed evidence into a believable
    /// stopped state. Negative and non-finite values remain unavailable, while
    /// signed zero is normalized only for stable presentation.
    private var validatedRenderValue: Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value == 0 ? 0 : value
    }

    /// Choose presentation capacity from the same explicit rounding contract used
    /// by `RollingNumberModel`. This is display geometry only, never a physical
    /// scooter-speed limit. Values beyond the three-digit cockpit capacity fail
    /// closed rather than being clamped or expanded into unbounded text.
    private func numberModel(for value: Double) -> RollingNumberModel? {
        let roundedValue = value.rounded(.toNearestOrAwayFromZero)
        switch roundedValue {
        case ...99:
            Self.twoDigitNumberModel
        case ...999:
            Self.threeDigitNumberModel
        default:
            nil
        }
    }

    var body: some View {
        if let value = validatedRenderValue,
           let numberModel = numberModel(for: value),
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
            // Newer frames retarget SwiftUI's current presentation immediately.
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
