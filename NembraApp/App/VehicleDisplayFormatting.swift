import Foundation

enum VehicleDisplayFormatting {
    static var usesMetric: Bool {
        Locale.current.measurementSystem == .metric
    }

    static func speed(kilometersPerHour: Double?, decimals: Int = 0) -> String {
        guard let kilometersPerHour,
              kilometersPerHour.isFinite,
              kilometersPerHour >= 0 else { return "—" }
        let value = usesMetric ? kilometersPerHour : kilometersPerHour * 0.621_371
        let unit = usesMetric ? "km/h" : "mph"
        return String(format: "%.*f %@", decimals, value, unit)
    }

    static func speed(kilometersPerHour: Int?) -> String {
        guard let kilometersPerHour, kilometersPerHour >= 0 else { return "—" }
        return speed(kilometersPerHour: Double(kilometersPerHour), decimals: 0)
    }

    static func distance(kilometers: Double?, decimals: Int = 1) -> String {
        guard let kilometers,
              kilometers.isFinite,
              kilometers >= 0 else { return "—" }
        let value = usesMetric ? kilometers : kilometers * 0.621_371
        let unit = usesMetric ? "km" : "mi"
        return String(format: "%.*f %@", decimals, value, unit)
    }
}
