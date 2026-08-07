/// Stable clock-field decomposition for an accepted cockpit duration value.
///
/// This is presentation arithmetic only. It never advances time and never becomes
/// ride evidence. `RideDurationCockpitValue` remains the authority-bearing
/// presentation projection; these fields exist so a future SwiftUI cockpit can
/// render fixed-geometry `MM:SS` / `H:MM:SS` digits without converting through
/// `Date`, floating-point seconds, or a display timer.
public struct RideDurationCockpitClockComponents: Equatable, Sendable {
    public let hours: UInt64
    public let minutes: UInt8
    public let seconds: UInt8

    public init(value: RideDurationCockpitValue) {
        let wholeSeconds = value.wholeObservedSeconds
        let secondsWithinHour = wholeSeconds % 3_600

        self.hours = wholeSeconds / 3_600
        self.minutes = UInt8(secondsWithinHour / 60)
        self.seconds = UInt8(secondsWithinHour % 60)
    }

    /// Whether presentation needs an explicit hour field rather than `MM:SS`.
    public var usesHourField: Bool {
        hours > 0
    }
}

public extension RideDurationCockpitValue {
    /// Clock fields derived only from the already-accepted whole-second render
    /// convenience. Subsecond evidence remains preserved on this value and is
    /// intentionally not rounded up into a later displayed second.
    var clockComponents: RideDurationCockpitClockComponents {
        RideDurationCockpitClockComponents(value: self)
    }
}
