/// Product-facing truth state for one battery field after freshness is evaluated.
///
/// A value becomes `verifiedLive` only when it is both fresh under an injected policy
/// and already classified as a physically verified vehicle measurement. Freshness alone
/// can never promote stock-app, Simulator, derived, or presentation-only evidence.
public enum BatteryEvidenceLiveTruthState: Equatable, Sendable {
    case unavailable
    case freshnessUnclassified(BatteryEvidenceObservation)
    case stale(BatteryEvidenceObservation, ageNanoseconds: UInt64)
    case freshNonAuthoritative(BatteryEvidenceObservation, ageNanoseconds: UInt64)
    case verifiedLive(BatteryEvidenceObservation, ageNanoseconds: UInt64)

    public var observation: BatteryEvidenceObservation? {
        switch self {
        case .unavailable:
            nil
        case let .freshnessUnclassified(observation),
             let .stale(observation, _),
             let .freshNonAuthoritative(observation, _),
             let .verifiedLive(observation, _):
            observation
        }
    }

    public var verifiedLiveObservation: BatteryEvidenceObservation? {
        if case let .verifiedLive(observation, _) = self {
            return observation
        }
        return nil
    }

    public var isVerifiedLive: Bool {
        verifiedLiveObservation != nil
    }
}

public struct BatteryEvidenceLiveTruthSnapshot: Equatable, Sendable {
    public let stateByField: [BatteryEvidenceField: BatteryEvidenceLiveTruthState]

    public init(stateByField: [BatteryEvidenceField: BatteryEvidenceLiveTruthState]) {
        self.stateByField = stateByField
    }

    public subscript(field: BatteryEvidenceField) -> BatteryEvidenceLiveTruthState {
        stateByField[field] ?? .unavailable
    }

    public func verifiedLiveObservation(for field: BatteryEvidenceField) -> BatteryEvidenceObservation? {
        self[field].verifiedLiveObservation
    }
}

/// Pure projection from freshness/availability into product live-truth state.
public enum BatteryEvidenceLiveTruthResolver {
    public static func resolve(
        _ availability: BatteryEvidenceFieldAvailability
    ) -> BatteryEvidenceLiveTruthState {
        switch availability {
        case .unavailable:
            .unavailable

        case let .unclassified(observation):
            .freshnessUnclassified(observation)

        case let .stale(observation, ageNanoseconds):
            .stale(observation, ageNanoseconds: ageNanoseconds)

        case let .fresh(observation, ageNanoseconds):
            if observation.isAuthoritativeVehicleMeasurement {
                .verifiedLive(observation, ageNanoseconds: ageNanoseconds)
            } else {
                .freshNonAuthoritative(observation, ageNanoseconds: ageNanoseconds)
            }
        }
    }

    public static func resolve(
        _ availabilitySnapshot: BatteryEvidenceAvailabilitySnapshot
    ) -> BatteryEvidenceLiveTruthSnapshot {
        var result: [BatteryEvidenceField: BatteryEvidenceLiveTruthState] = [:]
        result.reserveCapacity(BatteryEvidenceField.allCases.count)

        for field in BatteryEvidenceField.allCases {
            result[field] = resolve(availabilitySnapshot[field])
        }

        return BatteryEvidenceLiveTruthSnapshot(stateByField: result)
    }
}
