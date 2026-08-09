import Foundation

/// A battery observation that is eligible to cross from transport/application input
/// into shared product state.
///
/// The numeric percent and its authority are inseparable. A transport-delivered
/// integer with no established meaning must remain outside Battery/Range, Dashboard,
/// Home, Vehicle, ride records, and derived calculations until hardware evidence
/// assigns one of the explicit authorities below.
public struct AuthoritativeBatteryObservation: Equatable, Sendable {
    public let percent: Int
    public let authority: BatteryObservationAuthority
    public let observedAt: Date

    public init?(
        percent: Int,
        authority: BatteryObservationAuthority?,
        observedAt: Date
    ) {
        guard let authority,
              (0...100).contains(percent),
              observedAt.timeIntervalSince1970.isFinite else {
            return nil
        }

        self.percent = percent
        self.authority = authority
        self.observedAt = observedAt
    }

    /// Retention preserves the original observation authority and timestamp.
    /// `retainedAt` is storage chronology, not a new measurement time.
    public func retained(at retainedAt: Date = .now) -> RetainedBatterySnapshot? {
        RetainedBatterySnapshot(
            percent: percent,
            authority: authority,
            observedAt: observedAt,
            retainedAt: retainedAt
        )
    }

    /// Narrows an already-authoritative battery observation to evidence that may be
    /// treated as a validated physical/vehicle measurement by downstream physical
    /// calculations. Estimated and display-only values deliberately fail closed.
    ///
    /// This does not assign ES80 semantics. It only preserves the authority boundary
    /// established upstream once real hardware evidence exists.
    public var physicalMeasurement: PhysicalBatterySOCObservation? {
        PhysicalBatterySOCObservation(self)
    }

    /// Narrows further for range learning/estimation. A historical measured value is
    /// still physically meaningful, but it is not current remaining-range evidence.
    /// Range therefore requires both measured authority and explicit live currentness.
    public func rangeEligible(
        currentness: BatteryObservationCurrentness
    ) -> RangeEligibleBatterySOCObservation? {
        RangeEligibleBatterySOCObservation(self, currentness: currentness)
    }
}

/// Battery state that has crossed the stricter physical-measurement boundary.
///
/// Range learning, energy modeling, or any other physical calculation can accept this
/// type when it specifically requires measured SoC, preventing estimated/display-only
/// percentages from being silently reused as physical evidence.
public struct PhysicalBatterySOCObservation: Equatable, Sendable {
    public let percent: Int
    public let observedAt: Date

    public init?(_ observation: AuthoritativeBatteryObservation) {
        guard observation.authority == .measured else { return nil }
        self.percent = observation.percent
        self.observedAt = observation.observedAt
    }
}

/// Currentness is intentionally orthogonal to measurement authority.
///
/// A retained observation can still be a genuine historical measurement; retention
/// does not turn it into an estimate. Conversely, being live does not make an
/// estimated/display-only percentage a physical measurement.
public enum BatteryObservationCurrentness: String, Codable, Equatable, Sendable {
    case live
    case retained
}

/// Battery SoC that is safe to feed into a *current remaining-range* calculation.
///
/// This boundary is stricter than `PhysicalBatterySOCObservation`: the source must be
/// a measured observation and it must be live. A retained measured snapshot remains
/// valid historical evidence but cannot silently drive "range remaining now" after a
/// reconnect, relaunch, or telemetry gap.
public struct RangeEligibleBatterySOCObservation: Equatable, Sendable {
    public let percent: Int
    public let observedAt: Date

    public init?(
        _ observation: AuthoritativeBatteryObservation,
        currentness: BatteryObservationCurrentness
    ) {
        guard currentness == .live,
              let physical = observation.physicalMeasurement else {
            return nil
        }

        self.percent = physical.percent
        self.observedAt = physical.observedAt
    }
}
