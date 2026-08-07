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
        compactSpeed(kilometersPerHour: kilometersPerHour, decimals: decimals) ?? "—"
    }

    /// Semantic counterpart for assistive output. It deliberately shares the
    /// exact compact projection used by visible speed text, but replaces the
    /// punctuation sentinel with a word VoiceOver can communicate meaningfully.
    /// A retained qualifier is added only when a concrete compact value exists;
    /// unavailable/malformed evidence never becomes the awkward phrase
    /// "Last known, unavailable".
    static func accessibilitySpeed(
        kilometersPerHour: Double?,
        decimals: Int = 0,
        isRetained: Bool = false
    ) -> String {
        guard let compactSpeed = compactSpeed(
            kilometersPerHour: kilometersPerHour,
            decimals: decimals
        ) else {
            return "Unavailable"
        }

        return isRetained ? "Last known, \(compactSpeed)" : compactSpeed
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

    private static func compactSpeed(kilometersPerHour: Double?, decimals: Int) -> String? {
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0,
              (0...maximumSpeedFractionDigits).contains(decimals) else {
            return nil
        }

        let normalizedKilometersPerHour = kilometersPerHour == 0 ? 0 : kilometersPerHour
        // Capture one measurement-system decision for the complete projection so
        // the numeric conversion and its unit label cannot observe different
        // locale states during the same formatting call.
        let isMetric = usesMetric
        let value = isMetric
            ? normalizedKilometersPerHour
            : normalizedKilometersPerHour * 0.621_371
        guard value.isFinite, value >= 0 else { return nil }

        // Keep textual speed rounding identical to the rolling cockpit digits.
        // Foundation `%f` uses ties-to-even on half steps, while the cockpit's
        // accepted presentation rule is nearest-away-from-zero. Round explicitly
        // before formatting so Home/status/VoiceOver cannot disagree with the
        // visible speed at values such as 22.5 -> 23.
        let decimalScale = pow(10.0, Double(decimals))
        let roundedValue = (value * decimalScale)
            .rounded(.toNearestOrAwayFromZero) / decimalScale

        // Bound the already-rounded value rather than clamping it. This also
        // prevents a value such as 999.5 at zero decimals from becoming a
        // four-digit `1000` string after passing the representability gate.
        guard roundedValue.isFinite,
              roundedValue >= 0,
              roundedValue < maximumSpeedDisplayMagnitude else {
            return nil
        }

        let unit = isMetric ? "km/h" : "mph"
        return String(format: "%.*f %@", locale: Locale.current, decimals, roundedValue, unit)
    }
}
