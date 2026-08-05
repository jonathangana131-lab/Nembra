import SwiftUI

struct RollingSpeedValueView: View {
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
                ForEach(Array(snapshot.digits.enumerated()), id: \.offset) { _, digit in
                    Text(String(digit.digit))
                        .opacity(digit.isVisible ? 1 : 0)
                        .contentTransition(.numericText(value: value))
                }
            }
            .animation(.smooth(duration: 0.14), value: snapshot.scaledValue)
        } else if let value {
            Text(String(format: "%.0f", max(0, value)))
                .contentTransition(.numericText(value: value))
        } else {
            Text("—")
        }
    }
}
