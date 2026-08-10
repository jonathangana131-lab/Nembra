import Foundation

/// Deterministic, capture-local CoreBluetooth correlation for the physical target-selection gate.
///
/// This intentionally accepts only full peripheral UUID sets observed while the scooter is OFF/ON.
/// Names, RSSI, advertised services, manufacturer data, and any remembered UUID are excluded from
/// the authority API so descriptive hints cannot accidentally mint target identity.
public enum PeripheralPowerCycleCorrelation {
    public enum TransitionResolution: Equatable, Sendable {
        case missing
        case ambiguous(candidates: Set<UUID>)
        case unique(UUID)
    }

    public enum RepeatedResolution: Equatable, Sendable {
        case missingFirst
        case ambiguousFirst(candidates: Set<UUID>)
        case missingSecond
        case ambiguousSecond(candidates: Set<UUID>)
        case mismatch(first: UUID, second: UUID)
        case correlated(UUID)
    }

    public static func resolveTransition(
        off: Set<UUID>,
        on: Set<UUID>
    ) -> TransitionResolution {
        let appeared = on.subtracting(off)
        switch appeared.count {
        case 0:
            return .missing
        case 1:
            return .unique(appeared.first!)
        default:
            return .ambiguous(candidates: appeared)
        }
    }

    public static func resolveRepeated(
        off1: Set<UUID>,
        on1: Set<UUID>,
        off2: Set<UUID>,
        on2: Set<UUID>
    ) -> RepeatedResolution {
        let first = resolveTransition(off: off1, on: on1)
        switch first {
        case .missing:
            return .missingFirst
        case let .ambiguous(candidates):
            return .ambiguousFirst(candidates: candidates)
        case let .unique(firstID):
            let second = resolveTransition(off: off2, on: on2)
            switch second {
            case .missing:
                return .missingSecond
            case let .ambiguous(candidates):
                return .ambiguousSecond(candidates: candidates)
            case let .unique(secondID):
                guard firstID == secondID else {
                    return .mismatch(first: firstID, second: secondID)
                }
                return .correlated(firstID)
            }
        }
    }
}
