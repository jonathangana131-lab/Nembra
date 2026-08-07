import Foundation

enum VehicleDisplayFormatting {
    /// Speed text is used in compact vehicle surfaces and assistive output. This
    /// is a presentation capacity, not a physical scooter-speed limit: values
    /// that would require four integral digits fail closed instead of expanding
    /// an unbounded string or being clamped to believable vehicle state.
    private static let maximumSpeedDisplayMagnitude = 1_000.0
    private static let maximumSpeedFractionDigits = 3

    static var usesMetric: Bool {
        Locale.current.measurementSystem == .metric
    }

    static func speed(kilometersPerHour: Double?, decimals: Int = 0) -> String {
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0,
              (0...maximumSpeedFractionDigits).contains(decimals) else {
            return "—"
        }

        let normalizedKilometersPerHour = kilometersPerHour == 0 ? 0 : kilometersPerHour
        let value = usesMetric
            ? normalizedKilometersPerHour
            : normalizedKilometersPerHour * 0.621_371
        guard value.isFinite, value >= 0 else { return "—" }

        // `%f` is bounded only after the converted value is known to fit the
        // compact speed presentation. Account for decimal rounding so 999.5 at
        // zero decimals (or the equivalent boundary at higher precision) cannot
        // format as a four-digit `1000` after passing the guard.
        let decimalScale = pow(10.0, Double(decimals))
        let halfRoundingStep = 0.5 / decimalScale
        guard value < maximumSpeedDisplayMagnitude - halfRoundingStep else {
            return "—"
        }

        let unit = usesMetric ? "km/h" : "mph"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }

    static func speed(kilometersPerHour: Int?) -> String {
        guard let kilometersPerHour, kilometersPerHour >= 0 else { return "—" }
        return speed(kilometersPerHour: Double(kilometersPerHour), decimals: 0)
    }

    static func distance(kilometers: Double?, decimals: Int = 1) -> String {
        guard let kilometers, kilometers.isFinite, kilometers >= 0 else {
            return "—"
        }
        let normalizedKilometers = kilometers == 0 ? 0 : kilometers
        let value = usesMetric ? normalizedKilometers : normalizedKilometers * 0.621_371
        let unit = usesMetric ? "km" : "mi"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }
}
