import Foundation

/// Deterministic CoreBluetooth correlation for the next stationary ES80 capture attempt.
///
/// This gate intentionally knows nothing about display names, RSSI, services, manufacturer
/// hints, prior CoreBluetooth UUIDs, or Tuya protocol semantics. It answers one narrow question:
/// did exactly one current peripheral disappear in both OFF observations and appear in both ON
/// observations of the required OFF1 -> ON1 -> OFF2 -> ON2 sequence?
///
/// A positive result is correlation evidence for the current CoreBluetooth target only. It does
/// not establish durable scooter identity and does not replace same-account exact-device Tuya SDK
/// membership as the authentication source authority.
public enum TuyaRepeatedPowerCorrelationGate {
    public struct Snapshot: Equatable, Sendable {
        public let off1: Set<UUID>
        public let on1: Set<UUID>
        public let off2: Set<UUID>
        public let on2: Set<UUID>

        public init(
            off1: Set<UUID>,
            on1: Set<UUID>,
            off2: Set<UUID>,
            on2: Set<UUID>
        ) {
            self.off1 = off1
            self.on1 = on1
            self.off2 = off2
            self.on2 = on2
        }
    }

    public enum Blocker: Equatable, Sendable {
        /// No peripheral was present in both ON observations while absent from both OFF observations.
        case noRepeatablePowerOnOnlyCandidate

        /// More than one peripheral satisfies the physical correlation sequence, so choosing one
        /// would require an unaccepted tie-breaker such as name, RSSI, service hints, or history.
        case ambiguousRepeatablePowerOnOnlyCandidates([UUID])
    }

    public enum Verdict: Equatable, Sendable {
        /// The sole current peripheral correlated by the complete repeated power sequence.
        case correlated(peripheralID: UUID)
        case blocked(Blocker)
    }

    public static func verdict(for snapshot: Snapshot) -> Verdict {
        let repeatablyOn = snapshot.on1.intersection(snapshot.on2)
        let observedWhileOff = snapshot.off1.union(snapshot.off2)
        let candidates = repeatablyOn
            .subtracting(observedWhileOff)
            .sorted { $0.uuidString < $1.uuidString }

        switch candidates.count {
        case 1:
            return .correlated(peripheralID: candidates[0])
        case 0:
            return .blocked(.noRepeatablePowerOnOnlyCandidate)
        default:
            return .blocked(.ambiguousRepeatablePowerOnOnlyCandidates(candidates))
        }
    }
}
