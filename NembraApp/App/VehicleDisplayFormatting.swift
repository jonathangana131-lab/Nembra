import Foundation

enum VehicleDisplayFormatting {
    static var usesMetric: Bool {
        Locale.current.measurementSystem == .metric
    }

    static func speed(kilometersPerHour: Double?, decimals: Int = 0) -> String {
        guard let kilometersPerHour, kilometersPerHour.isFinite, kilometersPerHour >= 0 else {
            return "—"
        }
        let normalizedKilometersPerHour = kilometersPerHour == 0 ? 0 : kilometersPerHour
        let value = usesMetric ? normalizedKilometersPerHour : normalizedKilometersPerHour * 0.621_371
        let unit = usesMetric ? "km/h" : "mph"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }

    static func speed(kilometersPerHour: Int?) -> String {
        guard let kilometersPerHour, kilometersPerHour >= 0 else { return "—" }
        return speed(kilometersPerHour: Double(kilometersPerHour), decimals: 0)
    }

    /// Product-default distance presentation keeps useful precision for short,
    /// positive measurements instead of rounding real ride evidence down to
    /// "0.0" in the rider's preferred unit. This changes presentation only; it
    /// never manufactures distance or combines independent scooter/GPS sources.
    static func distance(kilometers: Double?) -> String {
        guard let kilometers, kilometers.isFinite, kilometers >= 0 else {
            return "—"
        }

        let normalizedKilometers = kilometers == 0 ? 0 : kilometers
        let value = usesMetric ? normalizedKilometers : normalizedKilometers * 0.621_371
        let decimals: Int
        if value == 0 {
            decimals = 1
        } else if value < 0.1 {
            decimals = 3
        } else if value < 1 {
            decimals = 2
        } else {
            decimals = 1
        }
        let unit = usesMetric ? "km" : "mi"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }

    /// Explicit precision remains available for surfaces that intentionally own
    /// a fixed numeric presentation contract.
    static func distance(kilometers: Double?, decimals: Int) -> String {
        guard let kilometers, kilometers.isFinite, kilometers >= 0 else {
            return "—"
        }
        let normalizedKilometers = kilometers == 0 ? 0 : kilometers
        let value = usesMetric ? normalizedKilometers : normalizedKilometers * 0.621_371
        let unit = usesMetric ? "km" : "mi"
        return String(format: "%.*f %@", locale: Locale.current, decimals, value, unit)
    }
}