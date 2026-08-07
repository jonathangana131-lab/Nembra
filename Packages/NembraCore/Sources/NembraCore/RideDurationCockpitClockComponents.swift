import Foundation

/// Stable clock-field decomposition for an accepted cockpit duration value.
///
/// This is presentation arithmetic only. It never advances time and never becomes
/// ride evidence. The source session, complete-vs-partial role, and accepted
/// whole-second value stay bound to the decomposed fields so a future SwiftUI
/// cockpit cannot accidentally detach plausible-looking digits from their truth
/// qualifier while rendering fixed-geometry `MM:SS` / `H:MM:SS` output.
public struct RideDurationCockpitClockComponents: Equatable, Sendable {
    public let sessionID: UUID
    public let role: RideDurationCockpitDisplayRole
    public let wholeObservedSeconds: UInt64
    public let hours: UInt64
    public let minutes: UInt8
    public let seconds: UInt8

    public init(value: RideDurationCockpitValue) {
        let wholeSeconds = value.wholeObservedSeconds
        let secondsWithinHour = wholeSeconds % 3_600

        self.sessionID = value.sessionID
        self.role = value.role
        self.wholeObservedSeconds = wholeSeconds
        self.hours = wholeSeconds / 3_600
        self.minutes = UInt8(secondsWithinHour / 60)
        self.seconds = UInt8(secondsWithinHour % 60)
    }

    /// Whether presentation needs an explicit hour field rather than `MM:SS`.
    /// This is layout guidance only and carries no evidence meaning.
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
