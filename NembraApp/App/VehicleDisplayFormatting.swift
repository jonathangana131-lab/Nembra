import Foundation

enum VehicleDisplayFormatting {
    /// Matches the compact Dashboard speed renderer's three-integer-digit fallback.
    /// This is a presentation capacity, never a physical scooter-speed limit or
    /// telemetry admission rule.
    private static let maximumCompactSpeedInteger = 999.0

    static var usesMetric: Bool {
        Locale.current.measurementSystem == .metric
    }

    static func speed(kilometersPerHour: Double?, decimals: Int = 0) -> String {
        compactSpeed(kilometersPerHour: kilometersPerHour, decimals: decimals) ?? "—"
    }

    /// Semantic VoiceOver counterpart to the compact visible speed projection.
    /// Unrepresentable presentation values are spoken as unavailable rather than
    /// exposing a punctuation sentinel or an overflowed `inf` conversion.
    static func accessibilitySpeed(kilometersPerHour: Double?, decimals: Int = 0) -> String {
        compactSpeed(kilometersPerHour: kilometersPerHour, decimals: decimals) ?? "Unavailable"
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
        guard let kilometersPerHour, kilometersPerHour.isFinite, kilometersPerHour >= 0 else {
            return nil
        }

        let normalizedKilometersPerHour = kilometersPerHour == 0 ? 0 : kilometersPerHour
        let value = usesMetric ? normalizedKilometersPerHour : normalizedKilometersPerHour * 0.621_371
        guard value.isFinite, value >= 0 else { return nil }

        // Keep the representability boundary identical to RollingSpeedValueView:
        // round as the integer cockpit readout would, then fail closed before any
        // conversion/formatting can expand an extreme finite Double into huge text.
        let roundedIntegerValue = value.rounded(.toNearestOrAwayFromZero)
        guard roundedIntegerValue <= maximumCompactSpeedInteger else { return nil }

        let unit = usesMetric ? "km/h" : "mph"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }
}
