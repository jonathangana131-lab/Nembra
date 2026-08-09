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
}
